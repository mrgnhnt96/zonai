import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../lib/gen/server/.revali/server/server.dart' as gen_server;

/// The generated server (`apps/zonai/lib/gen/server`, the same code
/// `zonai compile`/`zonai serve` embeds), bound in-process on a free port of
/// `127.0.0.1`.
///
/// See `admin_invite_http_oauth_e2e_test.dart` for why it is started
/// in-process rather than by shelling out to `zonai serve`, and why each
/// fixture needs its own test file (and so its own isolate).
class LiveServer {
  LiveServer._(this._httpServer, this._logBuffer);

  final HttpServer _httpServer;
  final StringBuffer? _logBuffer;

  /// Starts the server for the project [settings] point at.
  ///
  /// With [captureLogs], everything the server logs, at verbose level, is
  /// kept for [capturedLogOutput].
  static Future<LiveServer> start(
    Settings settings, {
    bool captureLogs = false,
  }) async {
    if (!captureLogs) {
      final httpServer = await runMergedScopedFuture(
        () => gen_server.createServer(null, const []),
        override: liveServerScopeOverrides(settings),
      );
      return LiveServer._(httpServer, null);
    }

    final logBuffer = StringBuffer();
    final logController = StreamController<List<int>>();
    logController.stream.transform(utf8.decoder).listen(logBuffer.write);
    final captureSink = IOSink(logController.sink);

    // Overriding `loggerProvider` is NOT enough to see request logging.
    //
    // `TraceId`'s lifecycle component re-overrides `loggerProvider` for the
    // duration of every request with `Logger.print(...)`
    // (`components/lifecycle_components/trace_id.dart`), which writes through
    // `PrintSink` -> Dart's `print`. The injected `captureSink` is discarded
    // at that point, so on its own it only ever holds the handful of startup
    // lines emitted before the first request, against which any
    // `isNot(contains(...))` passes for free.
    //
    // `print` is zone-scoped, so capturing the zone is what actually works.
    // The server's request loop is started inside `createServer` and inherits
    // this zone, so every later request logs through here. The line is still
    // forwarded to the parent zone: swallowing it would make a failing run
    // harder to read, and the buffer is for asserting on, not for hiding
    // output.
    final httpServer = await runZoned(
      () => runMergedScopedFuture(
        () => gen_server.createServer(null, const []),
        override: liveServerScopeOverrides(
          settings,
          logger: Logger(
            level: .verbose,
            stdout: captureSink,
            stderr: captureSink,
          ),
        ),
      ),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          logBuffer.writeln(line);
          parent.print(zone, line);
        },
      ),
    );

    return LiveServer._(httpServer, logBuffer);
  }

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.http('127.0.0.1:${_httpServer.port}', path, query);

  /// What the server has logged so far; only kept when started with
  /// `captureLogs: true`.
  String get capturedLogOutput {
    final buffer = _logBuffer;
    if (buffer == null) {
      throw StateError('LiveServer was started without captureLogs: true');
    }
    return buffer.toString();
  }

  Future<void> close() => _httpServer.close(force: true);
}

/// The scope [LiveServer] runs the generated server in.
///
/// Args, file system, logger and [settings] are the ones a test controls.
/// Everything else is at its production default and mirrors the registration
/// set in `apps/zonai/lib/src/bootstrap.dart`'s `runZonai`, the only place
/// this exact list is proven correct; keep the two in step.
///
/// The same set lets a test reach the server's own module-level singletons
/// (`zonaiDbProvider`, `operationsProvider`) from a separate
/// `runMergedScopedFuture` call.
Set<ScopedRef<dynamic>> liveServerScopeOverrides(
  Settings settings, {
  Logger? logger,
}) => {
  argsProvider.overrideWith(
    () => Args.parse(const ['--host=127.0.0.1', '--port=0']),
  ),
  fsProvider.overrideWith(LocalFileSystem.new),
  loggerProvider.overrideWith(() => logger ?? Logger(level: .error)),
  settingsProvider.overrideWith(() => settings),
  envProvider,
  courierProvider,
  processProvider,
  cleanUpProvider,
  mutationsProvider,
  keyboardInputProvider,
  messageContractHashProvider,
  migrateProvider,
  extensionsProvider,
  executableStopProvider,
  rulesProvider,
  rateLimitsProvider,
  cronsProvider,
  webhooksProvider,
  rateLimiterProvider,
  configProvider,
  configResolverProvider,
  killProvider,
  stdinProvider,
  operationsProvider,
  revaliProvider,
  zonaiDbProvider,
  versionsProvider,
  schemaVersionCheckProvider,
  dartSdkCheckProvider,
};
