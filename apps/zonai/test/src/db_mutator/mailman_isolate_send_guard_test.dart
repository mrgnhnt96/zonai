import 'dart:async';
import 'dart:collection';
import 'dart:io' as io;
import 'dart:isolate';

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

/// One unsendable value must not be able to take the host down.
///
/// The incident: a `count` on `subscriptions` crashed the host because the
/// rules payload carried an `UnmodifiableMapView` -- the perfectly ordinary
/// product of a defensive `toJson()`. Fixing the one `toJson()` that produced
/// it closes that instance. These two tests close the class, at the two places
/// in `Mailman` that let a single bad value do that much damage.
///
/// **The boundary.** `_sendOutbound` has two branches that were not
/// symmetric. The process branch runs `IpcCodec.encode`, a full MessagePack
/// pass that flattens the payload into plain collections before a byte goes
/// out. The isolate branch handed the live object graph to `SendPort.send`.
/// Isolate workers are spawned with `Isolate.spawnUri` (see
/// `_tryStartIsolate`), which starts a NEW isolate group, and across groups
/// the VM's serializer accepts only literal instances. The first test here
/// pins that refusal against a real spawned isolate rather than asserting it
/// from the documentation, because the whole defect was somebody reasonably
/// assuming `send` copies anything.
///
/// **The leak.** `_writeOnce` registers a pending completer *before* it sends,
/// which it has to: a worker can answer faster than the function resumes.
/// When the send threw, that entry stayed on `_pendingResponses` forever. It
/// is not what failed the request -- the error propagates out through `_send`
/// and the caller sees it either way -- but `_restartFromStopFile` drains with
/// `while (_pendingResponses.isNotEmpty)`, so one orphan wedges every
/// stop-file restart for the life of the process.
void main() {
  group('Mailman: the isolate send boundary', () {
    late io.Directory tempDir;
    late String workerPath;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync('mailman_send_guard');
      workerPath = '${tempDir.path}${io.Platform.pathSeparator}worker.dart';
      io.File(workerPath).writeAsStringSync(_workerSource);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('refuses a payload the normalizer has not been through, and '
        'carries the one it has', () async {
      final peer = await _EchoIsolate.spawn(workerPath);
      addTearDown(peer.dispose);

      // Nested on purpose: a shallow copy at the top level would pass a test
      // that only wrapped the outer map, and the incident's value was nested
      // (a `jwt` inside a request).
      final payload = <String, dynamic>{
        'path': 'request/.rule',
        'id': 'r1',
        'jwt': UnmodifiableMapView<String, Object?>({
          'sub': 'user-1',
          'claims': UnmodifiableMapView<String, Object?>({'role': 'admin'}),
          'scopes': UnmodifiableListView<Object?>(const ['read', 'write']),
        }),
      };

      expect(
        () => peer.send(payload),
        throwsA(isA<ArgumentError>()),
        reason:
            'if this ever stops throwing, the guard below is defending '
            'against nothing and this whole file should go',
      );

      expect(() => peer.send(toIsolateSendable(payload)), returnsNormally);

      // Contents, not just "it went": a normalizer that dropped the nested
      // map would also have satisfied the line above.
      expect(await peer.next, {
        'path': 'request/.rule',
        'id': 'r1',
        'jwt': {
          'sub': 'user-1',
          'claims': {'role': 'admin'},
          'scopes': ['read', 'write'],
        },
      });
    });

    test('carries a Mailman request whose payload is unmodifiable', () async {
      await runScoped(() async {
        final mailman = Mailman<Request, Response>(
          debugName: 'send-guard',
          // Deliberately absent, so once the isolate transport is up nothing
          // can quietly fall back to a worker process and pass this test on
          // the branch it is not about.
          executablePath: '${tempDir.path}/never-compiled.exe',
          sourceEntryPath: workerPath,
          fromJson: (_) => throw UnimplementedError('pong is already typed'),
        );
        // Before the guard this threw `ArgumentError: Invalid argument: is a
        // regular instance reachable via ... UnmodifiableMapView`, out of
        // `SendPort.send`, before the request ever reached a worker.
        try {
          final response = await mailman.send<Response?>(
            _UnmodifiableRequest(),
          );

          expect(response, isA<PongResponse>());
        } finally {
          // Inside the scope, not in an `addTearDown`: `dispose` -> `kill`
          // reads the scoped `logger`, and a tearDown runs after `runScoped`
          // has already unwound.
          await mailman.dispose();
        }
      }, values: _isolateScope());
    });
  });

  group('Mailman: a send that throws', () {
    late io.Directory tempDir;
    late String executablePath;

    setUp(() {
      tempDir = io.Directory.systemTemp.createTempSync('mailman_send_leak');
      executablePath = '${tempDir.path}${io.Platform.pathSeparator}worker.exe';
      // Never executed -- `process.start` is faked below. It only has to
      // exist so `hasExecutable` passes, and to carry no protocol/contract
      // stamp so the mismatch guards read null and decline to throw.
      io.File(executablePath).writeAsStringSync('not a real worker');
    });

    tearDown(() {
      _FakeLauncher.current = null;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('leaves nothing behind on _pendingResponses, and still throws to '
        'the caller', () async {
      await runScoped(() async {
        _FakeLauncher();
        final mailman = Mailman<Request, Response>(
          debugName: 'send-leak',
          executablePath: executablePath,
          fromJson: (_) => throw UnimplementedError(),
        );

        try {
          final request = _UnserializableRequest();

          await expectLater(
            mailman.send<Response?>(request),
            throwsA(isA<FormatException>()),
            reason: 'the caller must still see why its request failed',
          );

          expect(
            mailman.pendingResponseIds,
            isNot(contains(request.id)),
            reason: 'a completer nothing will ever complete was left behind',
          );
        } finally {
          await mailman.dispose();
        }
      }, values: _processScope());
    });

    test('does not wedge the next stop-file restart', () async {
      // The consequence, and the reason the entry above is worth removing at
      // all: `_restartFromStopFile` waits out `_pendingResponses` before it
      // clears the stop file. An orphan entry makes that a loop with no exit,
      // so `zonai serve`'s recompile-and-restart never fires again -- and it
      // fails as a hang, which reads as a slow machine rather than a bug.
      await runScoped(() async {
        _FakeLauncher();
        final mailman = Mailman<Request, Response>(
          debugName: 'send-leak-restart',
          executablePath: executablePath,
          fromJson: (_) => throw UnimplementedError(),
        );

        try {
          await expectLater(
            mailman.send<Response?>(_UnserializableRequest()),
            throwsA(isA<FormatException>()),
          );

          executableStop.request(executablePath);

          // `_ensureRestartedIfRequested` runs at the top of `_writeOnce`, so
          // any subsequent send is what drives the drain. The timeout is what
          // turns the defect from a hang into a failure: without it this test
          // waits out the suite's own 30s and blames the file, not the loop.
          await expectLater(
            mailman.ping().timeout(const Duration(seconds: 5)),
            completion(isTrue),
          );
          expect(executableStop.isRequested(executablePath), isFalse);
        } finally {
          executableStop.clear(executablePath);
          await mailman.dispose();
        }
      }, values: _processScope());
    });
  });
}

/// The deps a Mailman on the real isolate transport reaches for.
Set<ScopedRef<Object>> _isolateScope() => {
  settingsProvider.overrideWith(() => fakeSettings),
  fsProvider.overrideWith(LocalFileSystem.new),
  processProvider,
  cleanUpProvider,
  executableStopProvider,
  loggerProvider,
  mutationsProvider,
};

/// The same, with the process launcher faked.
Set<ScopedRef<Object>> _processScope() => {
  settingsProvider.overrideWith(() => fakeSettings),
  fsProvider.overrideWith(LocalFileSystem.new),
  processProvider.overrideWith(() => _FakeLauncher.current ?? Process()),
  cleanUpProvider,
  executableStopProvider,
  loggerProvider,
  mutationsProvider,
};

/// A worker that answers every request with a pong and echoes what it was
/// sent back to the host.
///
/// Written to disk rather than kept as a fixture file because
/// `Isolate.spawnUri` needs an absolute path and the JIT branch of
/// `_tryStartIsolate` needs a `.dart` source entry. It imports nothing but
/// `dart:isolate` on purpose: `spawnUri` is handed a package config only when
/// one happens to sit beside the current directory, so a worker that needed
/// `package:` resolution would pass or fail on where `dart test` was run
/// from.
const _workerSource = '''
import 'dart:isolate';

void main(List<String> args, SendPort host) {
  final local = ReceivePort();
  host.send(local.sendPort);
  local.listen((message) {
    if (message is! Map) return;
    // The echo rides inside the pong's payload, which `PongResponse.fromJson`
    // ignores, so one worker serves both the boundary test (which reads the
    // echo) and the Mailman test (which only needs a well-formed reply).
    host.send({
      'path': 'response/.pong',
      'id': message['id'],
      'payload': {'echo': message},
    });
  });
}
''';

/// A request whose `toJson()` hands back an unmodifiable view, the way a
/// `toJson()` that is defending its own internals does.
final class _UnmodifiableRequest extends Request {
  _UnmodifiableRequest() : super(path: '${Request.prefix}.guard', id: 'guard');

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'payload': UnmodifiableMapView<String, Object?>({
      'table': 'subscriptions',
      'where': UnmodifiableListView<Object?>(const ['id = 1']),
    }),
  };
}

/// A request nothing can serialize, so the send throws on either transport.
final class _UnserializableRequest extends Request {
  _UnserializableRequest()
    : super(path: '${Request.prefix}.guard', id: 'unserializable');

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'payload': Object()};
}

/// A live `Isolate.spawnUri` peer, so the sendability rules under test are the
/// VM's own and not this file's belief about them.
///
/// Replies are buffered into a plain list rather than a `Stream`. A
/// `StreamIterator` pauses its subscription between `moveNext()` calls, so a
/// controller closed in teardown never delivers its done event and the
/// `close()` future never completes -- a test that passes its assertions and
/// then hangs for the full 30s suite timeout, blaming nothing.
class _EchoIsolate {
  _EchoIsolate._(this._isolate, this._local, this._peer);

  static Future<_EchoIsolate> spawn(String workerPath) async {
    final local = ReceivePort();
    final peer = Completer<SendPort>();
    late final _EchoIsolate echo;

    local.listen((message) {
      if (message is SendPort && !peer.isCompleted) {
        peer.complete(message);
      } else {
        echo._deliver(message);
      }
    });

    final isolate = await Isolate.spawnUri(
      io.File(workerPath).absolute.uri,
      const [],
      local.sendPort,
    );

    return echo = _EchoIsolate._(
      isolate,
      local,
      await peer.future.timeout(const Duration(seconds: 10)),
    );
  }

  final Isolate _isolate;
  final ReceivePort _local;
  final SendPort _peer;

  final _replies = <Object?>[];
  Completer<void>? _waiting;

  void _deliver(Object? message) {
    _replies.add(message);
    _waiting?.complete();
    _waiting = null;
  }

  void send(Object? message) => _peer.send(message);

  /// What came back, minus the pong envelope the worker wraps it in.
  Future<Object?> get next async {
    if (_replies.isEmpty) {
      await (_waiting = Completer<void>()).future.timeout(
        const Duration(seconds: 10),
      );
    }
    final reply = _replies.removeAt(0)! as Map;
    return (reply['payload']! as Map)['echo'];
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _local.close();
  }
}

/// A [Process] launcher that answers [start] with an in-memory worker.
class _FakeLauncher extends Process {
  _FakeLauncher() {
    current = this;
  }

  /// The scope's `processProvider` is built lazily, after the launcher is
  /// constructed, so the two are joined here rather than through the
  /// constructor.
  static _FakeLauncher? current;

  /// A fresh worker per [start], not one reused across them. `_startOnce`
  /// subscribes to `stdout` on every spawn, and a stop-file restart spawns
  /// again -- handing back the same single-subscription stream fails the
  /// restart with `Bad state: Stream has already been listened to`, which is
  /// an artifact of the fake and not of anything Mailman does.
  final processes = <_FakeProcess>[];

  @override
  Future<io.Process> start(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) async {
    final process = _FakeProcess();
    processes.add(process);
    return process;
  }
}

/// A worker that answers `ping` and nothing else.
class _FakeProcess implements io.Process {
  _FakeProcess() {
    stdin = io.IOSink(_InboundFrames(_onRequest));
  }

  final _stdout = StreamController<List<int>>();
  final _exited = Completer<int>();

  @override
  late final Stream<List<int>> stdout = _stdout.stream;

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

  void _onRequest(Map<String, dynamic> request) {
    if (request['path'] != '${Request.prefix}.ping') return;
    if (_stdout.isClosed) return;
    _stdout.add(
      IpcCodec.encode(PongResponse(id: request['id'] as String).toJson()),
    );
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
