// Confirms the exact root cause of HybridStreamEngine entries never being
// cleaned up when a client of a long-lived /db/stream* connection goes
// away: revali_router's BodyImpl.read() wraps the response body in
// `.asBroadcastStream()` with no custom `onCancel`. That default onCancel
// PAUSES the underlying subscription rather than cancelling it once the
// last broadcast listener goes away -- documented Dart behavior, meant for
// sources that might get a *new* listener later and want to resume without
// losing data.
//
// HybridStreamEngine's entries are exactly the wrong shape for that
// default: they're long-lived and never externally closed while "live" --
// closing only happens as a *consequence* of onCancel firing (see
// hybrid_stream_engine.dart's _subscribe/_remove). Since nothing ever
// closes the source, the pause is permanent, onCancel never fires, and
// _remove(entry) never runs -- the entry (and its per-write requery cost)
// lives forever regardless of whether the client disconnected gracefully
// or abruptly.
//
// This reproduces the exact mechanism with zero HTTP/socket/
// HybridStreamEngine involvement -- pure `dart:async` -- so it's fast and
// unambiguous. Toggle `withFix` to see the difference: the default
// (broken) behavior vs. supplying `onCancel: (sub) => sub.cancel()` (what
// BodyImpl.read() should do).
import 'dart:async';

Future<bool> run({required bool withFix}) async {
  final c = StreamController<int>();
  var onCancelFired = false;
  c.onCancel = () => onCancelFired = true;

  final broadcast = withFix
      ? c.stream.asBroadcastStream(onCancel: (sub) => sub.cancel())
      : c.stream.asBroadcastStream();

  final sub = broadcast.listen((_) {});
  c.add(1);
  await Future<void>.delayed(const Duration(milliseconds: 20));

  // Mirrors a client disconnecting: the last (only) listener goes away.
  await sub.cancel();
  await Future<void>.delayed(const Duration(milliseconds: 20));

  // Mirrors subsequent writes to the watched table: HybridStreamEngine
  // would call entry.emit()/_read() again here. If onCancel never fired,
  // this data is silently dropped into a paused, orphaned subscription --
  // no error, no signal -- forever.
  for (var i = 2; i <= 5; i++) {
    c.add(i);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  return onCancelFired;
}

Future<void> main() async {
  final broken = await run(withFix: false);
  final fixed = await run(withFix: true);

  print('Default asBroadcastStream() (no onCancel):   onCancel fired = $broken');
  print('With onCancel: (sub) => sub.cancel():         onCancel fired = $fixed');
  print('');

  if (!broken && fixed) {
    print(
      'CONFIRMED: the default pause-not-cancel behavior is the root cause. '
      'revali_router\'s BodyImpl.read() (asBroadcastStream() call) needs a '
      'custom onCancel that actually cancels, or HybridStreamEngine entries '
      'for disconnected clients never get removed.',
    );
  } else {
    print('UNEXPECTED: this environment/SDK version behaves differently '
        'than documented -- re-investigate before trusting the analysis '
        'above.');
  }
}
