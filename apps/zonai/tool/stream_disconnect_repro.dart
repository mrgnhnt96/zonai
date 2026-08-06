// Repro for a suspected HybridStreamEngine leak mechanism: does cancelling
// the *client* side of a chunked HTTP response actually cancel the *source*
// stream feeding it, the way revali_router's DefaultResponseHandler wires it?
//
// DefaultResponseHandler (revali_router) does roughly:
//   await response.addStream(body);
// where `body` comes from BodyImpl.read(): `_data?.read()?.asBroadcastStream()`
// -- with no `onCancel` callback. Stream.asBroadcastStream()'s documented
// default onCancel is to *pause* the underlying subscription, not cancel it,
// once the last listener goes away. This script reproduces that exact wiring
// with a bare HttpServer, forcibly disconnects the client mid-stream (not a
// clean close), and reports whether the source ever sees onCancel.
//
// CORRECTED (2026-08-06): an earlier version of this script called
// `source.close()` right before checking the result, which itself forces a
// paused subscription to resolve and fire onCancel -- masking the real
// answer. Checking `sourceCancelled` *before* any explicit close (as below)
// shows the true behavior: onCancel never fires from the disconnect alone.
// See tool/hybrid_stream_cancel_repro.dart for the isolated, zero-HTTP
// confirmation and the fix (a custom `onCancel: (sub) => sub.cancel()`).
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  final source = StreamController<String>();
  var sourceCancelled = false;
  source.onCancel = () {
    sourceCancelled = true;
    stdout.writeln('[source] onCancel fired');
  };

  // Mirrors BodyImpl.read(): wrap in asBroadcastStream() with no onCancel arg.
  final body = source.stream.asBroadcastStream();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  stdout.writeln('Listening on ${server.address.address}:${server.port}');

  final serverDone = Completer<void>();
  server.listen((request) async {
    request.response.headers.set('Content-Type', 'text/plain');
    try {
      // Mirrors DefaultResponseHandler: await response.addStream(body).
      await request.response.addStream(
        body.map((s) => '$s\n'.codeUnits),
      );
      stdout.writeln('[server] addStream completed normally (unexpected)');
    } catch (e) {
      stdout.writeln('[server] addStream threw: $e');
    } finally {
      if (!serverDone.isCompleted) serverDone.complete();
    }
  });

  // Push one message per 200ms so the client has something to read before
  // and after the disconnect.
  var tick = 0;
  final pushTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
    tick++;
    if (source.isClosed) return;
    source.add('tick-$tick');
    stdout.writeln(
      '[source] pushed tick-$tick (isPaused=${source.isPaused})',
    );
  });

  final socket = await Socket.connect(
    server.address,
    server.port,
    timeout: const Duration(seconds: 5),
  );
  socket.write('GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n');
  await socket.flush();

  // Wait until at least one tick has been read back, proving the stream is
  // actually flowing end-to-end before we pull the rug.
  final firstByte = Completer<void>();
  final sub = socket.listen((data) {
    if (!firstByte.isCompleted) firstByte.complete();
  });
  await firstByte.future.timeout(const Duration(seconds: 5));
  await sub.cancel();

  stdout.writeln('--- destroying client socket abruptly (no clean FIN) ---');
  socket.destroy();

  // Give the disconnect a long window to propagate on its own -- no
  // explicit close() of anything yet, so this reports the TRUE effect of
  // the disconnect alone.
  await Future<void>.delayed(const Duration(seconds: 10));

  pushTimer.cancel();

  stdout.writeln('');
  stdout.writeln('=== RESULT ===');
  stdout.writeln('source.onCancel fired from the disconnect alone: $sourceCancelled');
  if (sourceCancelled) {
    stdout.writeln(
      'UNEXPECTED: the disconnect alone propagated back to the source '
      'stream. Re-investigate -- this contradicts hybrid_stream_cancel_repro.dart.',
    );
  } else {
    stdout.writeln(
      'CONFIRMED (leak mechanism real): the abrupt disconnect never reached '
      'the source stream on its own -- asBroadcastStream() only paused it, '
      'per its documented default. HybridStreamEngine\'s entry (and its '
      'StreamController) is never cleaned up on this path, and every '
      'subsequent write to a watched table queues into the orphaned '
      'controller forever. See tool/hybrid_stream_cancel_repro.dart for the '
      'minimal, zero-HTTP confirmation and fix.',
    );
  }

  // Only now close, for cleanup -- after the result is already recorded.
  await source.close();
  await server.close(force: true);
  exit(sourceCancelled ? 1 : 0);
}
