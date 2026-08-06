// Wave-based load generator for the `/db/stream*` routes, used to check
// whether HybridStreamEngine entries get cleaned up when a client goes away.
// Opens a batch of long-lived `GET /db/stream/list` connections, holds them
// briefly, then drops the whole batch either gracefully (cancel the
// subscription) or abruptly (force-close the socket), and repeats.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum DropMode { graceful, abrupt }

class StreamWaveStats {
  var wavesRun = 0;
  var streamsOpened = 0;
  var streamsDroppedGracefully = 0;
  var streamsDroppedAbruptly = 0;
  var openFailures = 0;
  var openTimeouts = 0;

  @override
  String toString() =>
      'waves=$wavesRun opened=$streamsOpened '
      'gracefulDrops=$streamsDroppedGracefully '
      'abruptDrops=$streamsDroppedAbruptly openFailures=$openFailures '
      'openTimeouts=$openTimeouts';
}

class _OpenStream {
  _OpenStream(this.client, this.subscription);
  final HttpClient client;
  final StreamSubscription<List<int>> subscription;
}

/// Opens waves of `GET /db/stream/list` connections against [baseUri], holds
/// each wave open for [holdDuration] while actively consuming bytes, then
/// drops every stream in the wave according to [dropMode]:
/// - [DropMode.graceful]: cancels the response subscription, then closes the
///   (per-connection) client non-forcibly -- a clean, client-initiated stop.
/// - [DropMode.abrupt]: `client.close(force: true)` -- the same idiom
///   load_runner.dart already uses for forced disconnects -- simulating a
///   client that vanishes without a clean HTTP close.
///
/// Repeats waves every [waveInterval] until [totalDuration] elapses.
Future<StreamWaveStats> runStreamWaves({
  required Uri baseUri,
  required Duration totalDuration,
  required Duration holdDuration,
  required Duration waveInterval,
  required int streamsPerWave,
  required DropMode dropMode,
}) async {
  final stats = StreamWaveStats();
  final deadline = DateTime.now().add(totalDuration);
  final body = utf8.encode(jsonEncode({'table': 'items', 'limit': 50}));
  final uri = baseUri.replace(path: '/db/stream/list');

  Future<_OpenStream?> openOne() async {
    // One HttpClient per connection (not shared/pooled) so an abrupt close
    // only kills this stream, not its wave-mates.
    final client = HttpClient();
    try {
      final opened = await Future(() async {
        final request = await client.openUrl('GET', uri);
        request.headers.contentType = ContentType.json;
        request.contentLength = body.length;
        request.add(body);
        final response = await request.close();
        final sub = response.listen(
          (_) {},
          onError: (_) {},
          cancelOnError: true,
        );
        return _OpenStream(client, sub);
      }).timeout(const Duration(seconds: 5));
      return opened;
    } on TimeoutException {
      // A wave is opened concurrently via Future.wait -- one connection that
      // never gets a response (rather than failing fast) would otherwise
      // hang the entire wave forever. Seen in practice under sustained
      // abrupt-disconnect load; worth its own counter since it may itself
      // be a symptom of server-side degradation under repeated disconnects.
      client.close(force: true);
      stats.openTimeouts++;
      return null;
    } catch (_) {
      client.close(force: true);
      stats.openFailures++;
      return null;
    }
  }

  Future<void> dropOne(_OpenStream stream) async {
    switch (dropMode) {
      case DropMode.graceful:
        try {
          await stream.subscription.cancel().timeout(const Duration(seconds: 5));
        } catch (_) {
          // Fall through to a forced close below either way.
        }
        stream.client.close(force: true);
        stats.streamsDroppedGracefully++;
      case DropMode.abrupt:
        stream.client.close(force: true);
        stats.streamsDroppedAbruptly++;
    }
  }

  while (DateTime.now().isBefore(deadline)) {
    stats.wavesRun++;
    final results = await Future.wait(
      List.generate(streamsPerWave, (_) => openOne()),
    );
    final opened = results.whereType<_OpenStream>().toList();
    stats.streamsOpened += opened.length;

    await Future<void>.delayed(holdDuration);

    for (final stream in opened) {
      await dropOne(stream);
    }

    final wait = waveInterval - holdDuration;
    final remaining = deadline.difference(DateTime.now());
    if (wait > Duration.zero && wait < remaining) {
      await Future<void>.delayed(wait);
    }
  }

  return stats;
}
