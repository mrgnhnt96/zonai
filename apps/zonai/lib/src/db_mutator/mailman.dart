import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:math' show min;

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/db_mutator/worker_transport.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/courier.dart';
import 'package:zonai/src/messengers/config_mailman.dart';
import 'package:zonai/src/messengers/cron_mailman.dart';
import 'package:zonai/src/messengers/extensions_mailman.dart';
import 'package:zonai/src/messengers/operations_mailman.dart';
import 'package:zonai/src/messengers/rate_limit_mailman.dart';
import 'package:zonai/src/messengers/rules_mailman.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    hide logger;
import 'package:zonai_schema/src/handlers/messages/message_io.dart'
    show coerceStringKeyedMap;

import '../db_mutator/executable_unavailable_exception.dart';
import '../db_mutator/payloads/payloads.dart';
import '../db_mutator/worker_contract_mismatch_exception.dart';
import '../db_mutator/worker_process_failed_exception.dart';
import '../db_mutator/worker_protocol_mismatch_exception.dart';
import '../deps/clean_up.dart';
import '../deps/executable_stop.dart';
import '../deps/fs.dart';
import '../deps/logger.dart';
import '../deps/mutations.dart';
import '../deps/process.dart';
import '../deps/settings.dart';
import '../deps/zonai_db.dart';
import '../domain/message_contract_stamp.dart';
import '../native/argon2_native.dart' show provideArgon2NativeLibraryPath;
import '../native/resqlite_native.dart' show provideResqliteNativeLibraryPath;

mixin Receivable<S extends Request, R extends Response> on Mailman<S, R> {
  Future<R> onRequest(S request);

  Future<void> onUnexpectedDelivery(R response);

  /// Worker notifications that reuse a pending RPC [Response.id] must not
  /// complete that RPC. Override when a worker pushes lifecycle events on the
  /// same id channel as request/reply pairs.
  bool isOutOfBandNotification(R response) => false;
}

class Mailman<S extends Request, R extends Response> {
  static final _loggedMissingExecutables = <String>{};
  static final _loggedProtocolMismatches = <String>{};
  static final _loggedContractMismatches = <String>{};
  static final _loggedStaleSnapshots = <String>{};
  static var _loggedInertContractGuard = false;

  Mailman({
    required this.debugName,
    required this.executablePath,
    required R Function(Map<String, dynamic>) fromJson,
    this.snapshotPath,
    this.sourceEntryPath,
    // Subprocess stdout preserves frame order (mutation RPCs before the reply).
    // Sync broadcast avoids delayed stream delivery; mutation [Request]s are
    // queued in [_listenToMessages] so enqueue cannot fall behind the next
    // response frame after an async [_handleRequest] await.
  }) : _response = StreamController.broadcast(sync: true),
       _request = StreamController.broadcast(sync: true),
       _fromJson = fromJson {
    cleanUp.add(dispose);
    _responseSubscription = _response.stream.listen(
      _handleResponse,
      onError: _onStreamError,
    );
    _requestSubscription = _request.stream.listen(
      _handleRequest,
      onError: _onStreamError,
    );
  }

  void _onStreamError(Object error, StackTrace stack) {
    logger.error('$_prefix: Stream handler error', error, stack);
  }

  final String debugName;
  final R Function(Map<String, dynamic>) _fromJson;
  final String executablePath;

  /// Optional AOT snapshot for [Isolate.spawnUri] (ops/rules).
  final String? snapshotPath;

  /// Optional generated `.dart` entry for JIT isolate spawn.
  final String? sourceEntryPath;

  io.Process? _process;
  Isolate? _isolate;
  SendPort? _isolatePeer;
  ReceivePort? _isolateLocal;
  StreamSubscription<dynamic>? _isolateSubscription;
  var _isolateHandshakeDone = false;
  Future<void>? _starting;

  /// Whether this worker has ever completed a round trip since it was last
  /// (re)started. Cleared on every fresh spawn in [_startOnce] so
  /// [_awaitOnce] can tell a genuinely cold worker (which still has to boot
  /// its runtime and open the DB before it can answer anything) apart from
  /// an already-established one that just isn't responding.
  var _warmedUp = false;
  final StringBuffer _stderrBuffer = StringBuffer();
  final IpcFrameBuffer _stdoutFrames = IpcFrameBuffer();
  final StreamController<Request> _request;
  late final StreamSubscription<Request> _requestSubscription;
  final StreamController<(Response, List<MutationRequest>)> _response;
  late final StreamSubscription<(Response, List<MutationRequest>)>
  _responseSubscription;

  final Map<String, Completer<(Response, List<MutationRequest>)>>
  _pendingResponses = {};
  final Map<String, List<MutationRequest>> _pendingMutations = {};

  Future<void>? _restartFuture;

  /// Serializes outbound writes so concurrent [_send] calls cannot interleave
  /// framed MessagePack / SendPort payloads.
  Future<void> _sendChain = Future.value();

  Future<void> dispose() async {
    kill();
    _response.close();
    _responseSubscription.cancel();
    _request.close();
    _requestSubscription.cancel();
  }

  String get _prefix => '[${debugName.toUpperCase()}_EXE]';

  String _executableRequiredMessage() {
    return switch (debugName) {
      ConfigMailman.debug =>
        'Config worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.configPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/config-and-env-flavors.md',
      OperationsMailman.debug =>
        'Operations worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.operationsPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/operations.md',

      RulesMailman.debug =>
        'Rules worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.rulesPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/rules.md',
      ExtensionsMailman.debug =>
        'Extensions worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.extensionsPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/extensions.md',
      RateLimitsMailman.debug =>
        'Rate limit worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.rateLimitPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/rate-limiting.md',
      CronMailman.debug =>
        'Cron worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.cronsPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/cron.md',
      _ =>
        'Worker is not compiled ($executablePath).\n'
            'Run `zonai serve` (or press c while serving) to compile workers.',
    };
  }

  ExecutableUnavailableException _logExecutableRequiredStack() {
    final error = ExecutableUnavailableException(
      workerName: debugName,
      executablePath: executablePath,
      message: _executableRequiredMessage(),
      stackTrace: StackTrace.current,
    );
    if (!_loggedMissingExecutables.add(executablePath)) return error;
    logger.error(error.message, error.runtimeType, error.stackTrace);
    return error;
  }

  Never _throwExecutableUnavailable() {
    throw _logExecutableRequiredStack();
  }

  /// Refuses to spawn [executablePath] when its compiled wire-protocol
  /// stamp doesn't match this host's own [IpcCodec.version] -- see
  /// `WorkerProtocolMismatchException.forStamp`.
  void _throwIfProtocolMismatch(String executablePath) {
    final error = WorkerProtocolMismatchException.forStamp(
      workerName: debugName,
      executablePath: executablePath,
      hostVersion: IpcCodec.version,
    );
    if (error == null) return;

    if (_loggedProtocolMismatches.add(executablePath)) {
      logger.error(error.message, error.runtimeType, StackTrace.current);
    }
    throw error;
  }

  /// Refuses to spawn [executablePath] when it was compiled against a
  /// different message vocabulary than this host speaks -- see
  /// `WorkerContractMismatchException.forStamp`.
  ///
  /// Runs at spawn, next to the protocol check, for the reason that check
  /// exists: a worker allowed this far fails inside a request handler, where
  /// the failure is an HTTP 5xx to whoever happened to be calling rather than
  /// a message to whoever can fix it.
  void _throwIfContractMismatch(String executablePath) {
    _warnIfContractGuardInert(executablePath);

    final error = WorkerContractMismatchException.forStamp(
      workerName: debugName,
      executablePath: executablePath,
      hostContract: hostMessageContractHash(),
    );
    if (error == null) return;

    if (_loggedContractMismatches.add(executablePath)) {
      logger.error(error.message, error.runtimeType, StackTrace.current);
    }
    throw error;
  }

  /// Says once, per process, that the contract guard cannot run here.
  ///
  /// Both guard sites pass an unknown host contract silently, and that is the
  /// right call -- a missing stamp is the ordinary state of an ad-hoc fixture,
  /// and refusing those would break far more than it caught. What was wrong is
  /// that the *published CLI serving a project directly* lands in that branch
  /// on every spawn (`kIsCompiled` is true, nothing stamped the binary, see
  /// [hostContractUnknownReason]), which is the default shape for a consumer,
  /// and it looked exactly like a guard that had run and found nothing.
  ///
  /// It does not add a refusal. There is nothing here to refuse *on*: with no
  /// host contract, a stale worker and a fresh one are the same observation.
  ///
  /// Only fires when [artifactPath] is stamped. With nothing stamped on either
  /// side no comparison was ever available to lose, and saying so on a project
  /// that has not run `zonai compile` yet would be noise, not news.
  void _warnIfContractGuardInert(String artifactPath) {
    if (_loggedInertContractGuard) return;
    if (hostMessageContractHash() != null) return;
    if (readMessageContractStamp(artifactPath) == null) return;

    final reason = hostContractUnknownReason();
    if (reason == null) return;

    _loggedInertContractGuard = true;
    logger.warn(
      '$_prefix: the message-contract check is not running -- $reason\n'
      'Workers beside this host are stamped, so there is drift to catch and '
      'nothing to catch it with: a worker built against a different '
      '`zonai_schema` vocabulary will start rather than be refused, and fail '
      'part-way through a request instead of at spawn.\n'
      'Run `zonai compile` after any `zonai_schema` change to keep them in '
      'step. A `zonai build` bundle stamps its own binary and does not have '
      'this gap.',
    );
  }

  Future<void> _deliverUnexpected(
    Future<void> Function(R response) onUnexpectedDelivery,
    R response,
  ) async {
    try {
      await onUnexpectedDelivery(response);
    } catch (error, stack) {
      logger.error(
        '$_prefix: Error handling worker notification',
        error,
        stack,
      );
    }
  }

  void _deliverUnexpectedWithEffects(
    Receivable<S, R> receivable,
    R response,
    List<MutationRequest> mutations,
  ) async {
    if (mutations.isNotEmpty) {
      try {
        await zonaiDB.commitEffects(mutations);
      } catch (error, stack) {
        logger.error('Failed to commit effects', error, stack);
      }
    }

    await _deliverUnexpected(receivable.onUnexpectedDelivery, response);
  }

  void _log(DebugResponse response) {
    switch (response.level) {
      case .debug:
        logger.debug(response.message, prefix: _prefix);
        return;
      case .info:
        logger.info(response.message);
        return;
      case .warn:
        logger.warn(response.message);
      case .error:
        logger.error(
          response.message,
          response.error,
          switch (response.stackTrace) {
            null => null,
            final trace => StackTrace.fromString(trace),
          },
        );
    }
    final jsonProps = switch (response.properties) {
      null => null,
      final props => JsonEncoder.withIndent('  ').convert(props),
    };
    if (jsonProps != null && jsonProps.isNotEmpty) {
      logger.debug(jsonProps, prefix: _prefix);
    }
  }

  void _handleRequest(Request request) async {
    Response response;
    try {
      switch (request) {
        case final GetRecordRequest request:
          response = await _fetch(request);

        case final NativeLibraryRequest request:
          response = await _provideNativeLibrary(request);

        case final PurgeRecordsRequest request:
          response = PurgeRecordsResponse(
            id: request.id,
            rowsAffected: await zonaiDB.purge(
              table: request.table,
              where: request.where,
              jwt: request.jwt,
            ),
          );

        case final Request request:
          if (this case Receivable(:final onRequest) when request is S) {
            response = await onRequest(request);
            break;
          }

          if (request is UnknownRequest) {
            logger.warn(
              'Unsupported extension worker request '
              '| path=${request.path}',
              prefix: _prefix,
            );
          }
          response = MessageErrorResponse(
            id: request.id,
            message:
                'Invalid worker request: ${request.runtimeType}(${request.path})',
            error: null,
            stackTrace: null,
          );
      }
    } on MessageHandlerFailedException catch (e) {
      response = MessageErrorResponse(
        id: request.id,
        message: e.message,
        error: e.cause,
        stackTrace: e.causeStackTrace,
      );
    } catch (e, stack) {
      logger.error('$_prefix: Error handling worker request', e, stack);
      response = MessageErrorResponse(
        id: request.id,
        message: 'Error handling worker request',
        error: e.toString(),
        stackTrace: stack.toString(),
      );
    }
    try {
      _sendOutbound(response.toJson());
    } on Object catch (e, stack) {
      logger.error('$_prefix: Failed to write to worker', e, stack);
    }
  }

  void _handleResponse(
    (Response response, List<MutationRequest> mutations) data,
  ) {
    final (response, mutations) = data;
    if (response is DebugResponse) {
      _log(response);
      return;
    }

    if (response case final MessageErrorResponse response) {
      logger.error(
        '$_prefix: ${response.message}',
        response.error,
        switch (response.stackTrace) {
          null => null,
          final trace => StackTrace.fromString(trace),
        },
      );

      _pendingMutations.remove(response.id);

      final completer = _pendingResponses.remove(response.id);
      if (completer == null) {
        logger.error(
          '$_prefix: Received error for unknown request: ${response.id}',
        );
        return;
      }

      completer.completeError(
        MessageHandlerFailedException(
          response.message,
          cause: response.error,
          causeStackTrace: response.stackTrace,
        ),
      );
      return;
    }

    if (_pendingResponses.containsKey(response.id)) {
      if (this case final Receivable<S, R> receivable when response is R) {
        if (receivable.isOutOfBandNotification(response)) {
          _deliverUnexpectedWithEffects(receivable, response, mutations);
          return;
        }
      }
    }

    final completer = _pendingResponses.remove(response.id);
    if (completer == null) {
      if (this case final Receivable<S, R> receivable when response is R) {
        _deliverUnexpectedWithEffects(receivable, response, mutations);
        return;
      }

      logger.error(
        '$_prefix: Received response for unknown request: ${response.path}',
      );
      return;
    }

    completer.complete((response, mutations));
  }

  bool get isRunning => _process != null || _isolate != null;
  bool get hasExecutable =>
      fs.file(executablePath).existsSync() || _hasIsolateAsset;

  bool get _hasIsolateAsset {
    if (snapshotPath != null && fs.file(snapshotPath!).existsSync()) {
      return true;
    }
    if (isRunningOnDartVm &&
        sourceEntryPath != null &&
        fs.file(sourceEntryPath!).existsSync()) {
      return true;
    }
    return false;
  }

  void _sendOutbound(Map<String, dynamic> message) {
    if (_isolatePeer case final peer?) {
      peer.send(message);
      return;
    }
    _process?.stdin.add(IpcCodec.encode(message));
  }

  Future<Response> _fetch(GetRecordRequest request) async {
    try {
      final results = await zonaiDB.list(
        request.table,
        ListWithJwtPayload(
          where: request.where,
          limit: request.limit,
          offset: request.offset,
          userJwt: request.jwt,
        ),
      );

      return GetRecordResponse(id: request.id, records: results.items);
    } catch (e, stack) {
      return MessageErrorResponse(
        id: request.id,
        message: 'Failed to get records',
        error: '$e',
        stackTrace: stack.toString(),
      );
    }
  }

  /// Answers a worker's [NativeLibraryRequest] by (re-)extracting *this*
  /// process's own embedded copy of the requested native library to the
  /// shared install path and reporting that path back.
  ///
  /// This process (the spawner) is always running natively on the machine
  /// both it and the worker are on right now -- unlike the worker, which
  /// may have been cross-compiled elsewhere -- so its own embedded copy is
  /// the correct one to hand back, regardless of what the worker's own
  /// embedded bytes might say.
  Future<Response> _provideNativeLibrary(NativeLibraryRequest request) async {
    try {
      final libraryPath = switch (request.library) {
        NativeLibraryKind.resqlite => await provideResqliteNativeLibraryPath(),
        NativeLibraryKind.argon2 => await provideArgon2NativeLibraryPath(),
      };

      return NativeLibraryResponse(id: request.id, libraryPath: libraryPath);
    } catch (e, stack) {
      return MessageErrorResponse(
        id: request.id,
        message: 'Failed to provide native library (${request.library.name})',
        error: '$e',
        stackTrace: stack.toString(),
      );
    }
  }

  Future<void> _start() async {
    if (isRunning) return;

    if (!hasExecutable) {
      return;
    }

    return _starting ??= _startOnce().whenComplete(() => _starting = null);
  }

  Future<void> _startOnce() async {
    if (isRunning) return;

    if (!hasExecutable) {
      return;
    }

    _warmedUp = false;

    final mode = workerTransportModeFromEnv();
    if (mode != WorkerTransportMode.process) {
      final started = await _tryStartIsolate();
      if (started) {
        logger.debug('Started isolate worker', prefix: _prefix);
        return;
      }
      if (mode == WorkerTransportMode.isolate) {
        logger.warn(
          '$_prefix: Isolate transport requested but failed; '
          'falling back to process',
        );
      }
    }

    if (!fs.file(executablePath).existsSync()) {
      return;
    }

    _throwIfProtocolMismatch(executablePath);
    _throwIfContractMismatch(executablePath);

    logger.debug('Starting | $executablePath', prefix: _prefix);

    _stderrBuffer.clear();
    _stdoutFrames.clear();
    // Argv is the only thing `ps`/Activity Monitor show for these workers,
    // and the executable path alone (`.zonai/executables/db_config.exe`) is
    // identical across every zonai project on a machine -- there is nothing
    // else outside the process that says which project a given worker PID
    // belongs to. The worker's generated `main()` takes no arguments (or
    // ignores them -- see rule_generator.dart/operation_generator.dart), so
    // this is inert to the worker itself and purely for outside attribution.
    final p = _process = await process.start(executablePath, [
      '--zonai-project=${settings.basePath ?? io.Directory.current.path}',
      '--zonai-worker=$debugName',
    ]);
    p.stderr
        .transform(utf8.decoder)
        .listen(_stderrBuffer.write, onError: _onStreamError);
    p.exitCode.then((exitCode) {
      try {
        if (!identical(_process, p)) return;

        final stderr = _stderrBuffer.toString();
        if (stderr.trim().isNotEmpty) {
          logger.error('$_prefix: stderr', stderr);
        }

        logger.warn('$_prefix: Exited (exit code: $exitCode)');
        _process = null;
        _stdoutFrames.clear();
        final failure = WorkerProcessFailedException(
          workerName: debugName,
          executablePath: executablePath,
          exitCode: exitCode,
          stderr: stderr,
        );
        for (final completer in _pendingResponses.values) {
          if (!completer.isCompleted) {
            completer.completeError(failure);
          }
        }
        _pendingResponses.clear();
        _pendingMutations.clear();
      } catch (error, stack) {
        _onStreamError(error, stack);
      }
    });

    p.stdout.listen(
      Zone.current.bindUnaryCallback<void, List<int>>(_onStdoutChunk),
      onError: _onStreamError,
    );

    logger.debug('Started', prefix: _prefix);
  }

  /// Whether the AOT snapshot at [path] was built against a different message
  /// vocabulary than this host speaks -- the isolate transport's version of
  /// `_throwIfContractMismatch`.
  ///
  /// Declines rather than throwing, which looks like a weaker guard and is
  /// not. Returning `false` from [_tryStartIsolate] falls through to the
  /// worker process, which is stamped separately and refuses loudly on its
  /// own if it is stale too -- so a genuinely stale pair still fails at spawn
  /// with the full message. What this buys is the case the two have diverged:
  /// the `.exe` and the `.aot` are separate compiles of the same sources
  /// (rules.dart's `compileArgs` note records the time they came out
  /// differently), so a stale snapshot beside a fresh executable should cost
  /// in-process dispatch, not the request.
  bool _snapshotContractIsStale(String path) {
    _warnIfContractGuardInert(path);

    final hostContract = hostMessageContractHash();
    if (!isMessageContractStale(path, hostHash: hostContract)) return false;

    if (_loggedStaleSnapshots.add(path)) {
      logger.warn(
        '$_prefix: $path was built against message contract '
        '${_shortContract(readMessageContractStamp(path))} but this host '
        'speaks ${_shortContract(hostContract)} -- ignoring it and using the '
        'worker process instead (dispatch still works, in-process does not). '
        'Run `zonai compile` to refresh it, or `zonai build` and redeploy if '
        'this host is a deployed bundle.',
      );
    }
    return true;
  }

  static String _shortContract(String? hash) =>
      hash == null ? 'nothing' : hash.substring(0, min(12, hash.length));

  Future<bool> _tryStartIsolate() async {
    Uri? entry;
    Uri? packageConfig;
    var fromSnapshot = false;

    if (isRunningOnDartVm &&
        sourceEntryPath != null &&
        fs.file(sourceEntryPath!).existsSync()) {
      entry = Uri.file(fs.file(sourceEntryPath!).absolute.path);
      final pkg = fs.file('.dart_tool/package_config.json');
      if (pkg.existsSync()) {
        packageConfig = Uri.file(pkg.absolute.path);
      }
    } else if (snapshotPath != null && fs.file(snapshotPath!).existsSync()) {
      if (_snapshotContractIsStale(snapshotPath!)) return false;
      entry = Uri.file(fs.file(snapshotPath!).absolute.path);
      fromSnapshot = true;
    } else {
      return false;
    }

    final local = ReceivePort();
    final errors = ReceivePort();
    try {
      _isolateHandshakeDone = false;
      _isolateLocal = local;
      _isolateSubscription = local.listen(
        _onIsolateMessage,
        onError: _onStreamError,
      );
      errors.listen((error) {
        logger.error('$_prefix: Isolate error', error);
      });

      _isolate = await Isolate.spawnUri(
        entry,
        const [],
        local.sendPort,
        onError: errors.sendPort,
        packageConfig: packageConfig,
      );

      // Wait for worker to send its SendPort (see SendPortMessageIo).
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!_isolateHandshakeDone) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Isolate worker handshake timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return _isolatePeer != null;
    } catch (e, stack) {
      // A snapshot that is present and will not spawn is worth saying out loud:
      // the fallback to the .exe worker serves identically, so this is the only
      // moment the loss of in-process dispatch is observable at all. The most
      // likely cause on a deployed bundle is a snapshot built for the build
      // host rather than the target.
      if (fromSnapshot) {
        logger.warn(
          '$_prefix: $snapshotPath would not spawn, falling back to the '
          'worker process (dispatch still works, in-process does not): $e',
        );
      } else {
        logger.debug('Isolate spawn failed: $e', prefix: _prefix);
      }
      logger.debug('$stack', prefix: _prefix);
      await _tearDownIsolate();
      return false;
    } finally {
      errors.close();
    }
  }

  void _onIsolateMessage(dynamic raw) {
    if (!_isolateHandshakeDone) {
      if (raw is SendPort) {
        _isolatePeer = raw;
        _isolateHandshakeDone = true;
      }
      return;
    }
    if (raw is! Map) {
      logger.error(
        '$_prefix: Isolate message was not a Map (${raw.runtimeType})',
      );
      return;
    }
    _listenToMessages(coerceStringKeyedMap(raw));
  }

  Future<void> _tearDownIsolate() async {
    await _isolateSubscription?.cancel();
    _isolateSubscription = null;
    _isolateLocal?.close();
    _isolateLocal = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolatePeer = null;
    _isolateHandshakeDone = false;
  }

  void _onStdoutChunk(List<int> chunk) {
    final List<Map<String, dynamic>> maps;
    try {
      maps = _stdoutFrames.push(chunk);
    } on FormatException catch (e, stack) {
      logger.error('$_prefix: Malformed IPC frame on stdout', e, stack);
      return;
    }

    for (final map in maps) {
      _listenToMessages(map);
    }
  }

  void _listenToMessages(Map<String, dynamic> json) {
    final pathRaw = json['path'];
    if (pathRaw is! String) {
      logger.error('$_prefix: Message missing path');
      return;
    }

    switch (pathRaw) {
      case final p when p.startsWith(Response.prefix):
        Response response;
        try {
          response = Response.fromJson(json);
        } on Object catch (e, stack) {
          logger.error(
            '$_prefix: Invalid response payload for path "$pathRaw"',
            e,
            stack,
          );
          return;
        }

        if (response is DebugResponse) {
          _response.add((response, <MutationRequest>[]));
          return;
        }

        final mutations = _pendingMutations.remove(response.id);
        _response.add((response, mutations ?? []));

      case final p when p.startsWith(Request.prefix):
        Request request;
        try {
          request = Request.fromJson(json);
        } on Object catch (e, stack) {
          logger.error(
            '$_prefix: Invalid request payload for path "$pathRaw"',
            e,
            stack,
          );
          return;
        }

        switch (request) {
          case final SendEmailRequest request:
            courier.send(request.email);
          case final SendBuiltInEmailRequest request:
            _sendBuiltInEmail(request);
          case final MutationRequest mutation:
            (_pendingMutations[mutation.parent.id] ??= []).add(mutation);

          default:
            _request.add(request);
        }
      case _:
        logger.error(
          '$_prefix: Unknown path prefix '
          '(expected "${Response.prefix}" or "${Request.prefix}"): '
          '$pathRaw',
        );
    }
  }

  void _sendBuiltInEmail(SendBuiltInEmailRequest request) {
    switch (request.builtIn) {
      case .otp:
        zonaiDB.sendOtp(
          request.table,
          SendOtpAuthPayload(email: request.to.address, object: request.object),
          jwt: request.jwt,
        );

      case .verifyEmail:
        zonaiDB.sendVerifyEmail(
          request.table,
          email: request.to.address,
          variables: request.object,
          jwt: request.jwt,
        );

      case .passwordReset:
        zonaiDB.sendResetPassword(
          request.table,
          ResetPasswordAuthPayload(email: request.to.address),
        );

      case .confirmEmailChange:
      case .magicLink:
      case .loginNotice:
        throw UnimplementedError('${request.builtIn} not implemented');
    }
  }

  Future<T> send<T extends R?>(S request) async {
    final _mutations = mutations;
    return await runMergedScopedFuture(() async {
      final response = await _send(request);

      if (response == null) {
        if (!hasExecutable) {
          _throwExecutableUnavailable();
        }

        if (null is T) {
          return null as T;
        }

        throw StateError('Invalid response: Got Null, expected $T');
      }

      if (response case final T response) {
        return response;
      }

      // Worker replies are parsed in Response.fromJson; an empty payload cannot
      // be re-decoded into a typed Response (etc.).
      if (response is R) {
        throw StateError(
          'Invalid response: Got ${response.runtimeType}, expected $T',
        );
      }

      final payload = response.payload;

      if (_fromJson(payload) case final T result) {
        return result;
      }

      throw StateError(
        'Invalid response: Got ${response.runtimeType}, expected $T',
      );
    }, override: {mutationsProvider.overrideWith(() => _mutations)});
  }

  /// Restarts the worker when a `.stop` file exists, after in-flight requests finish.
  Future<void> _ensureRestartedIfRequested() async {
    if (!executableStop.isRequested(executablePath)) return;

    if (_restartFuture case final restart?) {
      await restart;
      return;
    }

    final restart = _restartFuture = _restartFromStopFile();
    try {
      await restart;
    } finally {
      if (identical(_restartFuture, restart)) {
        _restartFuture = null;
      }
    }
  }

  Future<void> _restartFromStopFile() async {
    if (!executableStop.isRequested(executablePath)) return;

    if (!isRunning) {
      executableStop.clear(executablePath);
      return;
    }

    while (_pendingResponses.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 5));
    }

    executableStop.clear(executablePath);

    if (isRunning) {
      logger.debug('Restarting after stop file', prefix: _prefix);
      await kill(failPending: false);
    }
  }

  Future<Response?> _send(Request request) {
    final write = _sendChain.then((_) => _writeOnce(request));
    _sendChain = write.then((_) {}, onError: (_) {});
    return write.then((pendingResponse) {
      if (pendingResponse == null) return null;
      return _awaitOnce(request, pendingResponse);
    });
  }

  /// Ensures the worker is running (restarting first if a stop was
  /// requested) and writes [request] to its stdin, serialized via
  /// [_sendChain] so writes can't interleave on the wire and a pending
  /// restart can't race a write to the about-to-be-killed process.
  ///
  /// Deliberately does not wait for the reply — a worker's own handler for
  /// an incoming request can issue its own nested request back through
  /// this same Mailman (e.g. a row rule calling `get.one`) before it's
  /// replied to that incoming request. Waiting for the reply here too
  /// would serialize that nested send behind its own still-outstanding
  /// outer request, which can never resolve: a genuine deadlock, not just
  /// a slow path.
  Future<Completer<(Response, List<MutationRequest>)>?> _writeOnce(
    Request request,
  ) async {
    await _ensureRestartedIfRequested();

    await _start();
    if (!isRunning) {
      if (hasExecutable) {
        logger.debug('Skipping send of request: $request', prefix: _prefix);
      }
      return null;
    }

    final pendingResponse = Completer<(Response, List<MutationRequest>)>();
    _pendingResponses[request.id] = pendingResponse;

    _sendOutbound(request.toJson());
    return pendingResponse;
  }

  /// Steady-state request/reply timeout for an already-established worker —
  /// deliberately tight so a genuinely stuck worker fails fast.
  static const _warmRequestTimeout = Duration(seconds: 1);

  /// Request/reply timeout while [_warmedUp] is still false, i.e. no
  /// request has completed since this worker was last (re)started. A freshly
  /// spawned worker still has to boot its runtime and open the DB before it
  /// can answer anything; under concurrent load (several workers cold
  /// starting at once) that alone can take longer than [_warmRequestTimeout].
  /// Matches the generous timeout already used elsewhere for other
  /// first-contact worker operations (see resqlite_native.dart's
  /// `_requestFromSpawner`).
  static const _coldStartRequestTimeout = Duration(seconds: 10);

  Future<Response?> _awaitOnce(
    Request request,
    Completer<(Response, List<MutationRequest>)> pendingResponse,
  ) async {
    try {
      final (response, muts) = await pendingResponse.future.timeout(
        _warmedUp ? _warmRequestTimeout : _coldStartRequestTimeout,
      );
      _warmedUp = true;

      final recorded = mutations.addAll(muts);
      if (!recorded && muts.isNotEmpty) {
        logger.warn(
          'Dropped ${muts.length} mutations | ${request.path}',
          prefix: _prefix,
        );
      } else if (recorded && muts.isNotEmpty) {
        logger.trace(
          'Queued ${muts.length} mutations | ${request.path}',
          prefix: _prefix,
        );
      }

      return response;
    } on MessageHandlerFailedException {
      rethrow;
    } on WorkerProcessFailedException {
      rethrow;
    } catch (e, stack) {
      _pendingResponses.remove(request.id);
      _pendingMutations.remove(request.id);
      Error.throwWithStackTrace(
        WorkerProcessFailedException(
          workerName: debugName,
          executablePath: executablePath,
          cause: e,
          stackTrace: stack,
        ),
        stack,
      );
    }
  }

  Future<bool> ping() async {
    logger.debug('Pinging $executablePath', prefix: _prefix);
    final response = await _send(RequestPing());
    if (response == null) {
      logger.debug('Failed to ping', prefix: _prefix);
      return false;
    }

    return switch (response) {
      PongResponse() => true,
      _ => false,
    };
  }

  /// Stops the process and clears all pending responses
  ///
  /// Should only be called during development,
  /// and should never be called in production
  Future<void> kill({bool failPending = true}) async {
    if (_starting case final starting?) {
      await starting.catchError((_) => null);
      _starting = null;
    }

    if (_process case final process?) {
      logger.debug('Killing', prefix: _prefix);
      process.kill();
      _process = null;
      _stdoutFrames.clear();
    }

    if (_isolate != null) {
      logger.debug('Killing isolate', prefix: _prefix);
      await _tearDownIsolate();
    }

    _pendingMutations.clear();

    if (!failPending) return;

    final stderr = _stderrBuffer.toString();
    final failure = WorkerProcessFailedException(
      workerName: debugName,
      executablePath: executablePath,
      stderr: stderr,
      cause: 'Process killed',
    );
    for (final completer in _pendingResponses.values) {
      completer.completeError(failure);
    }

    _pendingResponses.clear();
  }
}

/// A small pool of independent [Mailman] worker subprocesses of the same
/// kind, round-robining [send] calls across them.
///
/// A single [Mailman] talks to one OS process over one stdin/stdout framed
/// MessagePack protocol (see [Mailman._sendChain] / `_writeOnce`). However many
/// CPU cores the host has, requests routed through one worker are bottlenecked
/// by that one process reading and replying to one frame at a time --
/// measured under load, that ceiling shows up as throughput *degrading*
/// past a handful of concurrent callers, not scaling with them. Running N
/// independent worker processes and spreading requests across them turns
/// one serial pipe into N parallel ones.
///
/// Only pool **stateless per-request** workers, where handling request A
/// has no bearing on how request B is handled -- rules, extensions, and
/// operations all qualify (each call is a pure function of its request).
/// Do **not** pool workers with singleton or scheduling semantics: the cron
/// worker, for example, must run each scheduled job exactly once, and
/// pooling it would run every job N times.
class MailmanPool<
  S extends Request,
  R extends Response,
  M extends Mailman<S, R>
> {
  MailmanPool(M Function() create, {int? size})
    : _workers = List.generate(size ?? defaultPoolSize, (_) => create());

  /// Defaults to 1 (one worker, identical footprint to the unpooled
  /// [Mailman]) -- pooling is opt-in via `ZONAI_WORKER_POOL_SIZE`. Every
  /// `ZonaiDb` (one per server, but also one per test/e2e setup, and tests
  /// run many of those concurrently) spawns its own pool, so a bigger
  /// default multiplies process count across every concurrent instance,
  /// not just the one production server it was meant to help. A single
  /// deployment that wants the throughput can set
  /// `ZONAI_WORKER_POOL_SIZE=4` (or similar, capped by available cores)
  /// deliberately.
  static int get defaultPoolSize {
    final override = int.tryParse(
      io.Platform.environment['ZONAI_WORKER_POOL_SIZE'] ?? '',
    );
    if (override != null && override > 0) {
      return min(override, io.Platform.numberOfProcessors * 2);
    }
    return 1;
  }

  final List<M> _workers;
  int _next = 0;

  M _pick() => _workers[_next++ % _workers.length];

  Future<T> send<T extends R?>(S request) => _pick().send<T>(request);

  Future<void> dispose() async {
    await Future.wait(_workers.map((w) => w.dispose()));
  }
}
