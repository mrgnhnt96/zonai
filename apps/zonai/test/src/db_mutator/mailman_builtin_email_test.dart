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
import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

/// Issue #41: a worker's request for a built-in email the host has not
/// implemented must not take the worker's REPLY down with it.
///
/// The default `AuthExtension.onSignIn` asks for `loginNotice`. The host
/// threw `UnimplementedError` for it from inside `_listenToMessages`, while it
/// was working through one stdout chunk -- so every message after it in that
/// chunk, including the worker's reply to the request in flight, was never
/// handled. The caller waited out its timeout and the request answered 503.
///
/// The fake worker below answers `ping` with exactly that chunk: the email
/// request first, the reply second.
void main() {
  late io.Directory tempDir;
  late String executablePath;

  setUp(() {
    tempDir = io.Directory.systemTemp.createTempSync('mailman_builtin_email');
    executablePath = '${tempDir.path}${io.Platform.pathSeparator}worker.exe';
    io.File(executablePath).writeAsStringSync('not a real worker');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // The first three are the unimplemented kinds. `verifyEmail` IS implemented,
  // and throws here only because this scope has no database -- it stands for
  // any message whose handling fails, and pins the per-message isolation on
  // its own: with it removed, this case goes red even though the three above
  // no longer throw at all.
  for (final builtIn in [
    BuiltInEmails.loginNotice,
    BuiltInEmails.magicLink,
    BuiltInEmails.confirmEmailChange,
    BuiltInEmails.verifyEmail,
  ]) {
    test('a ${builtIn.name} request does not swallow the reply that shares '
        'its chunk', () async {
      final escaped = <Object>[];
      Object? outcome;
      final done = Completer<void>();

      runZonedGuarded(
        () async {
          await runScoped(() async {
            _FakeLauncher(builtIn);
            final mailman = Mailman<Request, Response>(
              debugName: 'builtin-email',
              executablePath: executablePath,
              fromJson: (_) => throw UnimplementedError(),
            );
            try {
              outcome = await mailman.ping().timeout(
                const Duration(seconds: 3),
              );
            } on Object catch (e) {
              outcome = e;
            } finally {
              await mailman.dispose();
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

      expect(outcome, isTrue, reason: 'the reply after the email was lost');
      expect(escaped, isEmpty, reason: 'nothing may escape into the zone');
    });
  }
}

Set<ScopedRef<Object>> _scope() => {
  settingsProvider.overrideWith(() => fakeSettings),
  fsProvider.overrideWith(LocalFileSystem.new),
  processProvider.overrideWith(() => _FakeLauncher.current ?? Process()),
  cleanUpProvider,
  executableStopProvider,
  loggerProvider,
  mutationsProvider,
};

class _FakeLauncher extends Process {
  _FakeLauncher(this.builtIn) {
    current = this;
  }

  static _FakeLauncher? current;

  final BuiltInEmails builtIn;

  late final _FakeProcess process = _FakeProcess(builtIn);

  @override
  Future<io.Process> start(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) async => process;
}

/// A worker that answers `ping` with a built-in email request and then the
/// pong, in ONE stdout chunk.
class _FakeProcess implements io.Process {
  _FakeProcess(this.builtIn) {
    stdin = io.IOSink(_InboundFrames(_onRequest));
  }

  final BuiltInEmails builtIn;
  final _stdout = StreamController<List<int>>();
  final _exited = Completer<int>();

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
    final email = SendBuiltInEmailRequest(
      builtIn,
      table: 'users',
      to: const EmailAddress(address: 'ann@example.com'),
    );
    _stdout.add([
      ...IpcCodec.encode(email.toJson()),
      ...IpcCodec.encode(PongResponse(id: request['id'] as String).toJson()),
    ]);
  }
}

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
