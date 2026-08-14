// Wave-based load generator for the `/db/stream*` routes, used to check
// whether HybridStreamEngine entries get cleaned up when a client goes away.
// Opens a batch of long-lived stream connections -- mixing list/one/count
// and varying their parameters so each one is a genuinely distinct query
// (HybridStreamEngine caches one entry per distinct (sql, params), so
// hitting the same query every time only ever exercises a single entry) --
// holds them briefly, then drops the whole batch either gracefully (cancel
// the subscription) or abruptly (force-close the socket), and repeats.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum DropMode { graceful, abrupt }

enum _StreamKind { list, one, count }

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

final _random = Random();

/// Opens waves of stream connections against [baseUri], mixing
/// `/db/stream/list`, `/db/stream` (one), and `/db/stream/count`, each with
/// varied parameters (`limit` for list; a `where: id eq <one of [knownIds]>`
/// for one/count) so waves create many distinct HybridStreamEngine entries
/// instead of repeatedly hitting the same cached one. Holds each wave open
/// for [holdDuration] while actively consuming bytes, then drops every
/// stream in the wave according to [dropMode]:
/// - [DropMode.graceful]: cancels the response subscription, then closes the
///   (per-connection) client non-forcibly -- a clean, client-initiated stop.
/// - [DropMode.abrupt]: `client.close(force: true)` -- the same idiom
///   load_runner.dart already uses for forced disconnects -- simulating a
///   client that vanishes without a clean HTTP close.
///
/// [knownIds] should be real row ids (e.g. seeded via `createItem`) --
/// `/db/stream` (one) throws before ever reaching HybridStreamEngine if its
/// `where` matches no row, so exercising it meaningfully requires real data.
///
/// Repeats waves every [waveInterval] until [totalDuration] elapses.
Future<StreamWaveStats> runStreamWaves({
  required Uri baseUri,
  required Duration totalDuration,
  required Duration holdDuration,
  required Duration waveInterval,
  required int streamsPerWave,
  required DropMode dropMode,
  required List<String> knownIds,
}) async {
  final stats = StreamWaveStats();
  final deadline = DateTime.now().add(totalDuration);

  (Uri, List<int>) requestFor(_StreamKind kind) {
    switch (kind) {
      case _StreamKind.list:
        final limit = 1 + _random.nextInt(50);
        final offset = _random.nextInt(50);
        return (
          baseUri.replace(path: '/db/stream/list'),
          utf8.encode(
            jsonEncode({'table': 'items', 'limit': limit, 'offset': offset}),
          ),
        );
      case _StreamKind.one:
        final id = knownIds[_random.nextInt(knownIds.length)];
        return (
          baseUri.replace(path: '/db/stream'),
          utf8.encode(
            jsonEncode({
              'table': 'items',
              'where': {'type': 'eq', 'column': 'id', 'value': id},
              'expand': <String>[],
            }),
          ),
        );
      case _StreamKind.count:
        final id = knownIds[_random.nextInt(knownIds.length)];
        return (
          baseUri.replace(path: '/db/stream/count'),
          utf8.encode(
            jsonEncode({
              'table': 'items',
              'where': {'type': 'eq', 'column': 'id', 'value': id},
            }),
          ),
        );
    }
  }

  Future<_OpenStream?> openOne() async {
    // One HttpClient per connection (not shared/pooled) so an abrupt close
    // only kills this stream, not its wave-mates.
    final client = HttpClient();
    final kind = knownIds.isEmpty
        ? _StreamKind.list
        : _StreamKind.values[_random.nextInt(_StreamKind.values.length)];
    final (uri, body) = requestFor(kind);
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
          await stream.subscription.cancel().timeout(
            const Duration(seconds: 5),
          );
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
