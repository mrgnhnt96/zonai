import 'dart:async';
import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/worker_process_failed_exception.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/mutations.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/process.dart';
import 'package:zonai/src/messengers/extensions_mailman.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    hide logger;

import '../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

/// A warm worker that takes longer than 1s to answer.
///
/// Seen on haymay: an `afterCreateSuccess` hook ran past the 1s warm
/// timeout, the host called the extensions worker failed, and the admin was
/// told a row it had just saved had not been. The warm timeout is now per
/// Mailman, so a worker running app code can be given room the compute-only
/// workers do not need.
void main() {
  group('Mailman: warm request timeout', () {
    late io.Directory tempDir;
    late String executablePath;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync('mailman_warm_timeout');
      // Never executed -- `process.start` is faked. It only has to exist.
      executablePath = '${tempDir.path}${io.Platform.pathSeparator}worker.exe';
      io.File(executablePath).writeAsStringSync('not a real worker');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Warms a Mailman with one fast ping, then pings again with the worker
    /// taking [replyDelay] to answer.
    Future<Object?> slowSecondPing({
      required Duration replyDelay,
      Duration? warmRequestTimeout,
    }) async {
      return runScoped(() async {
        final launcher = _FakeLauncher();
        final mailman = Mailman<Request, Response>(
          debugName: 'warm-timeout',
          executablePath: executablePath,
          fromJson: (_) => throw UnimplementedError('ping never re-decodes'),
          warmRequestTimeout:
              warmRequestTimeout ?? Mailman.defaultWarmRequestTimeout,
        );
        try {
          expect(await mailman.ping(), isTrue, reason: 'the warm-up ping');

          launcher.process.replyDelay = replyDelay;
          try {
            return await mailman.ping();
          } on Object catch (e) {
            return e;
          }
        } finally {
          await mailman.dispose();
        }
      }, values: _scope());
    }

    test('a reply slower than the 1s default fails the request', () async {
      final outcome = await slowSecondPing(
        replyDelay: const Duration(milliseconds: 1500),
      );

      expect(
        outcome,
        isA<WorkerProcessFailedException>(),
        reason: 'pins the default, so the test below proves the override',
      );
    });

    test('a longer warmRequestTimeout waits the slow reply out', () async {
      final outcome = await slowSecondPing(
        replyDelay: const Duration(milliseconds: 1500),
        warmRequestTimeout: const Duration(seconds: 5),
      );

      expect(outcome, isTrue);
    });

    test('the extensions worker waits past the 1s default', () async {
      // Hooks are app code that does I/O. Back at 1s, a slow after-hook's
      // queued writes are dropped and a slow before-hook fails its request.
      final mailman = runScoped(ExtensionsMailman.new, values: _scope());
      addTearDown(mailman.dispose);

      expect(mailman.warmRequestTimeout, ExtensionsMailman.requestTimeout);
      expect(
        mailman.warmRequestTimeout,
        greaterThan(Mailman.defaultWarmRequestTimeout),
      );
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
  _FakeLauncher() {
    current = this;
  }

  /// The scope's `processProvider` is built lazily, after the launcher is
  /// constructed, so the two are joined here rather than through the
  /// constructor.
  static _FakeLauncher? current;

  final process = _FakeProcess();

  @override
  Future<io.Process> start(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) async => process;
}

/// A worker that answers `ping`, after [replyDelay].
class _FakeProcess implements io.Process {
  _FakeProcess() {
    stdin = io.IOSink(_InboundFrames(_onRequest));
  }

  final _stdout = StreamController<List<int>>();
  final _exited = Completer<int>();

  var replyDelay = Duration.zero;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  late final io.IOSink stdin;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exited.future;

  @override
  int get pid => 4243;

  @override
  bool kill([io.ProcessSignal signal = io.ProcessSignal.sigterm]) {
    if (!_exited.isCompleted) _exited.complete(-15);
    return true;
  }

  void _onRequest(Map<String, dynamic> request) {
    if (request['path'] != '${Request.prefix}.ping') return;
    final reply = IpcCodec.encode(
      PongResponse(id: request['id'] as String).toJson(),
    );
    Future<void>.delayed(replyDelay, () {
      if (!_stdout.isClosed) _stdout.add(reply);
    });
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
