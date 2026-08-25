import 'dart:async';
import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/mutations.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/process.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    hide logger;

import '../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

/// A worker's last words must not crash the host, or blame the wrong test.
///
/// The defect this file pins: `Mailman._listenToMessages` added to
/// `_response` with no check that `_response` was still open, while nothing
/// stopped a killed worker's stdout from arriving. `dispose()` kills the
/// process and closes the controller in the same breath, but
/// `process.kill()` is a *signal*, not a barrier -- the worker can get one
/// more frame out, and the kernel can hand us bytes it had already buffered.
/// The `add` then threw `Bad state: Cannot add new events after calling
/// close`.
///
/// **The crash is the smaller half.** `_onStdoutChunk` is bound (via
/// `Zone.current.bindUnaryCallback` in `_startOnce`) to the zone that
/// STARTED the worker -- not the one running when the late chunk lands. So
/// under `dart test` the error is reported against a test that had already
/// passed, which fails with "This test failed after it had already
/// completed". Three unrelated tests in
/// `test/e2e/forced_password_reset_e2e_test.dart` failed that way, and the
/// misattribution is what makes it expensive: it sends the next person
/// debugging a test that is fine.
///
/// The e2e reproduction is real but intermittent -- it needs the extensions
/// worker spawning on every auth event, which only happens once the fixture
/// registers any extension at all (`_detectProjectExtensions()` is
/// per-PROJECT, not per-table). These tests reproduce the same race
/// deterministically, at the seam, by faking the process.
///
/// Two defenses, one per test, deliberately pinned apart: `kill()` now
/// cancels the stdout subscription (stops the flow at the source), and
/// `_listenToMessages` drops anything arriving once `_disposed` is set (the
/// only defense left on the paths where the cancel does not run).
void main() {
  group('Mailman: a late stdout chunk', () {
    late io.Directory tempDir;
    late String executablePath;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync('mailman_late_chunk');
      // Never executed -- `process.start` is faked below. It only has to
      // exist, so `hasExecutable` passes, and to carry no protocol/contract
      // stamp, so `_throwIfProtocolMismatch`/`_throwIfContractMismatch` read
      // null and decline to throw.
      executablePath = '${tempDir.path}${io.Platform.pathSeparator}worker.exe';
      io.File(executablePath).writeAsStringSync('not a real worker');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Starts a Mailman, pings it, disposes it, then delivers one more
    /// frame -- and reports both what escaped into the zone the worker was
    /// started in (the zone the defect reports into) and what the stdout
    /// subscription saw.
    ///
    /// [honourCancel] is the only difference between the two tests.
    Future<(List<Object> escaped, _ObservedStream stdout)> deliverLateChunk({
      required bool honourCancel,
    }) async {
      final escaped = <Object>[];
      final done = Completer<void>();
      late _ObservedStream observed;

      runZonedGuarded(
        () async {
          await runScoped(() async {
            final launcher = _FakeLauncher(
              wrapStdout: (inner) =>
                  observed = _ObservedStream(inner, honourCancel: honourCancel),
            );
            final mailman = Mailman<Request, Response>(
              debugName: 'late-chunk',
              executablePath: executablePath,
              fromJson: (_) =>
                  throw UnimplementedError('ping never re-decodes'),
            );

            // A real round trip first: this is what starts the worker and
            // binds `_onStdoutChunk` to THIS zone.
            expect(await mailman.ping(), isTrue);

            await mailman.dispose();

            // The late chunk: a well-formed reply the worker got out
            // before it died. Same shape as the one that was in flight, so
            // nothing here is malformed -- the only thing wrong with it is
            // when it arrived.
            observed.late = true;
            launcher.process.emit(
              IpcCodec.encode(PongResponse(id: 'late').toJson()),
            );

            // Two full event-loop turns: enough for a delivered chunk to
            // be parsed and for the throw to reach the zone handler.
            await Future<void>.delayed(Duration.zero);
            await Future<void>.delayed(Duration.zero);
          }, values: _scope());
          done.complete();
        },
        (error, stack) {
          escaped.add(error);
          if (!done.isCompleted) done.complete();
        },
      );

      await done.future;
      return (escaped, observed);
    }

    test('never reaches the host, because kill() cancelled the '
        'subscription', () async {
      final (escaped, stdout) = await deliverLateChunk(honourCancel: true);

      // The load-bearing assertion is `cancelled`: without it the other two
      // pass for the wrong reason (the guard silently absorbing everything),
      // and the subscription `_start` opens on every spawn would still leak
      // across a restart.
      expect(stdout.cancelled, isTrue, reason: 'kill() must cancel stdout');
      expect(stdout.deliveredWhileLate, 0);
      expect(escaped, isEmpty);
    });

    test('does not STRAND a caller that reaches a disposed Mailman', () async {
      // The regression the first version of the `_disposed` guard shipped
      // with. Its comment claimed "kill() has already completed every entry
      // in _pendingResponses, so a late reply has no caller left" -- true for
      // a reply to a request sent BEFORE dispose, and false for this:
      //
      //   `_send` queues `_writeOnce` behind `_sendChain`. If dispose() runs
      //   while a send is still queued, the continuation then calls
      //   `_start()` -- which sees `isRunning == false`, spawns a FRESH
      //   worker, registers a completer on the map kill() has already
      //   drained, and writes the request. The worker answers; the guard
      //   drops the answer; nothing will ever drain that map again.
      //
      // Measured on the forced-password-reset e2e before this fix: a
      // `config.get` that is answered in ~15ms became a 10s
      // `TimeoutException` ("CONFIG worker failed"), reported against a test
      // that had already passed. Silence is a worse failure than an error --
      // it is indistinguishable from a hung worker, and it is what sent this
      // investigation looking at timeouts instead of at teardown.
      final escaped = <Object>[];
      final done = Completer<void>();
      Object? outcome;

      runZonedGuarded(
        () async {
          await runScoped(() async {
            _FakeLauncher();
            final mailman = Mailman<Request, Response>(
              debugName: 'stranded',
              executablePath: executablePath,
              fromJson: (_) => throw UnimplementedError(),
            );

            await mailman.dispose();

            // Well under `_coldStartRequestTimeout` (10s), so a pass here
            // means it answered rather than waited the timeout out.
            try {
              outcome = await mailman.ping().timeout(
                const Duration(seconds: 2),
              );
            } on Object catch (e) {
              outcome = e;
            }
          }, values: _scope());
          done.complete();
        },
        (error, stack) {
          escaped.add(error);
          if (!done.isCompleted) done.complete();
        },
      );

      await done.future;

      expect(
        outcome,
        isNot(isA<TimeoutException>()),
        reason: 'the caller was stranded waiting for a reply that was dropped',
      );
      expect(outcome, isFalse, reason: 'a disposed worker cannot be pinged');
      expect(escaped, isEmpty);
    });

    test('is DROPPED, not added, when it reaches the host anyway', () async {
      // Cancelling a subscription cannot un-dispatch a callback the runtime
      // has already scheduled, and on the isolate transport -- or when the
      // worker had already exited, so `kill()`'s `_process` branch is
      // skipped -- there is no stdout subscription to cancel in the first
      // place. Ignoring the cancel models that, leaving the `_disposed`
      // guard in `_listenToMessages` as the only thing standing between a
      // late frame and a closed controller.
      final (escaped, stdout) = await deliverLateChunk(honourCancel: false);

      expect(
        stdout.deliveredWhileLate,
        greaterThan(0),
        reason:
            'the chunk must actually reach _onStdoutChunk, or this test '
            'proves nothing about the guard',
      );
      expect(escaped, isEmpty);
    });
  });
}

/// The deps `Mailman` reaches for, with the process launcher faked.
Set<ScopedRef<Object>> _scope() => {
  settingsProvider.overrideWith(() => fakeSettings),
  fsProvider.overrideWith(LocalFileSystem.new),
  processProvider.overrideWith(() => _FakeLauncher.current ?? Process()),
  cleanUpProvider,
  executableStopProvider,
  loggerProvider,
  mutationsProvider,
};

/// A [Process] launcher that answers [start] with an in-memory worker.
class _FakeLauncher extends Process {
  _FakeLauncher({Stream<List<int>> Function(Stream<List<int>>)? wrapStdout})
    : _wrapStdout = wrapStdout {
    current = this;
  }

  /// The scope's `processProvider` is built lazily, after the launcher is
  /// constructed, so the two are joined here rather than through the
  /// constructor.
  static _FakeLauncher? current;

  final Stream<List<int>> Function(Stream<List<int>>)? _wrapStdout;

  late final _FakeProcess process = _FakeProcess(wrapStdout: _wrapStdout);

  @override
  Future<io.Process> start(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) async => process;
}

/// A worker that answers `ping` and nothing else.
class _FakeProcess implements io.Process {
  _FakeProcess({Stream<List<int>> Function(Stream<List<int>>)? wrapStdout}) {
    final raw = _stdout.stream;
    stdout = wrapStdout == null ? raw : wrapStdout(raw);
    stdin = io.IOSink(_InboundFrames(_onRequest));
  }

  final _stdout = StreamController<List<int>>();
  final _exited = Completer<int>();

  @override
  late final Stream<List<int>> stdout;

  @override
  late final io.IOSink stdin;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exited.future;

  @override
  int get pid => 4242;

  @override
  bool kill([io.ProcessSignal signal = io.ProcessSignal.sigterm]) {
    if (!_exited.isCompleted) _exited.complete(-15);
    return true;
  }

  void emit(List<int> frame) {
    if (_stdout.isClosed) return;
    _stdout.add(frame);
  }

  void _onRequest(Map<String, dynamic> request) {
    if (request['path'] != '${Request.prefix}.ping') return;
    emit(IpcCodec.encode(PongResponse(id: request['id'] as String).toJson()));
  }
}

/// Decodes what the host writes to the fake worker's stdin.
class _InboundFrames implements StreamConsumer<List<int>> {
  _InboundFrames(this._onFrame);

  final void Function(Map<String, dynamic>) _onFrame;
  final _frames = IpcFrameBuffer();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach((chunk) => _frames.push(chunk).forEach(_onFrame));

  @override
  Future<void> close() async {}
}

/// Wraps the fake worker's stdout so a test can see what the host's
/// subscription actually did: whether it was cancelled, and whether any
/// chunk was handed over after that.
///
/// With [honourCancel] false it delivers regardless -- the one thing
/// cancelling cannot undo is a callback the runtime has already dispatched,
/// and that is the case the `_disposed` guard exists for.
class _ObservedStream extends Stream<List<int>> {
  _ObservedStream(this._inner, {required this.honourCancel});

  final Stream<List<int>> _inner;
  final bool honourCancel;

  var cancelled = false;

  /// Set by the test immediately before the late frame is emitted, so
  /// [deliveredWhileLate] counts only that frame and not the ping's reply.
  /// Deliberately independent of [cancelled]: keyed off the cancel, this
  /// would read zero whenever `kill()` failed to cancel at all, and the test
  /// meant to pin the guard would pass or fail for the other defense's
  /// reasons.
  var late = false;
  var deliveredWhileLate = 0;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _ObservedSubscription(
      this,
      _inner.listen(
        (chunk) {
          if (cancelled && honourCancel) return;
          if (late) deliveredWhileLate++;
          onData?.call(chunk);
        },
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
    );
  }
}

class _ObservedSubscription implements StreamSubscription<List<int>> {
  _ObservedSubscription(this._owner, this._inner);

  final _ObservedStream _owner;
  final StreamSubscription<List<int>> _inner;

  @override
  Future<void> cancel() async {
    _owner.cancelled = true;
    if (_owner.honourCancel) await _inner.cancel();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void onData(void Function(List<int> data)? handleData) =>
      _inner.onData(handleData);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();
}
