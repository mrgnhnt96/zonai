import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/courier.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    hide logger;

import '../db_mutator/executable_unavailable_exception.dart';
import '../db_mutator/worker_process_failed_exception.dart';
import '../db_mutator/payloads/payloads.dart';
import '../deps/clean_up.dart';
import '../deps/executable_stop.dart';
import '../deps/fs.dart';
import '../deps/logger.dart';
import '../deps/mutations.dart';
import '../deps/process.dart';
import '../deps/settings.dart';
import '../deps/zonai_db.dart';

class Mailman<S extends Request, R extends Response> {
  static final _loggedMissingExecutables = <String>{};

  Mailman({
    required this.debugName,
    required this.executablePath,
    required R Function(Map<String, dynamic>) fromJson,
    // Subprocess stdout preserves line order (mutation RPCs before the reply).
    // Sync broadcast avoids delayed stream delivery; mutation [Request]s are
    // queued in [_listenToMessages] so enqueue cannot fall behind the next
    // response line after an async [_handleRequest] await.
  }) : _response = StreamController.broadcast(sync: true),
       _request = StreamController.broadcast(sync: true),
       _fromJson = fromJson {
    cleanUp.add(dispose);
    _responseSubscription = _response.stream.listen(_handleResponse);
    _requestSubscription = _request.stream.listen(_handleRequest);
  }

  final String debugName;
  final R Function(Map<String, dynamic>) _fromJson;
  final String executablePath;

  io.Process? _process;
  final StringBuffer _stderrBuffer = StringBuffer();
  final StreamController<Request> _request;
  late final StreamSubscription<Request> _requestSubscription;
  final StreamController<(Response, List<MutationRequest>)> _response;
  late final StreamSubscription<(Response, List<MutationRequest>)>
  _responseSubscription;

  final Map<String, Completer<(Response, List<MutationRequest>)>>
  _pendingResponses = {};
  final Map<String, List<MutationRequest>> _pendingMutations = {};

  Future<void>? _restartFuture;

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
      'CONFIG' =>
        'Config worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.configPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/config-and-env-flavors.md',
      'OPERATIONS' =>
        'Operations worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.operationsPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/operations.md',

      'RULES' =>
        'Rules worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.rulesPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/rules.md',
      'EXTENSIONS' =>
        'Extensions worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.extensionsPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/extensions.md',
      'RATE_LIMIT' =>
        'Rate limit worker is not compiled ($executablePath).\n'
            'Add Dart files under ${settings.rateLimitPath} and run `zonai serve` '
            '(or press c while serving) to compile workers.\n'
            'See docs/rate-limiting.md',
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

        case final Request request:
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
      _process?.stdin.writeln(jsonEncode(response.toJson()));
    } on Object catch (e, stack) {
      logger.error('$_prefix: Failed to write to child stdin', e, stack);
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

    final completer = _pendingResponses.remove(response.id);
    if (completer == null) {
      logger.error(
        '$_prefix: Received response for unknown request: ${response.path}',
      );
      return;
    }

    completer.complete((response, mutations));
  }

  bool get isRunning => _process != null;
  bool get hasExecutable => fs.file(executablePath).existsSync();

  Future<Response> _fetch(GetRecordRequest request) async {
    try {
      final results = await zonaiDB.list(
        request.collection,
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

  Future<io.Process?> _start() async {
    if (_process case final process?) {
      return process;
    }

    if (!hasExecutable) {
      return null;
    }

    logger.debug('Starting | $executablePath', prefix: _prefix);

    _stderrBuffer.clear();
    final p = _process = await process.start(executablePath, []);
    p.stderr.transform(utf8.decoder).listen(_stderrBuffer.write);
    p.exitCode.then((exitCode) {
      if (!identical(_process, p)) return;

      final stderr = _stderrBuffer.toString();
      if (stderr.trim().isNotEmpty) {
        logger.error('$_prefix: stderr', stderr);
      }

      logger.warn('$_prefix: Exited (exit code: $exitCode)');
      _process = null;
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
    });

    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          Zone.current.bindUnaryCallback<void, String>(_listenToMessages),
        );

    logger.debug('Started', prefix: _prefix);

    return p;
  }

  void _listenToMessages(String message) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(message.trim()) as Map<String, dynamic>;
    } on Object catch (e, stack) {
      logger.error('$_prefix: Malformed message on stdout', e, stack);
      return;
    }

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
            '$_prefix: Invalid response JSON for path "$pathRaw"',
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
            '$_prefix: Invalid request JSON for path "$pathRaw"',
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
          request.collection,
          SendOtpAuthPayload(email: request.to.address, object: request.object),
          jwt: request.jwt,
        );

      case .verifyEmail:
        zonaiDB.sendVerifyEmail(
          request.collection,
          email: request.to.address,
          variables: request.object,
          jwt: request.jwt,
        );

      case .passwordReset:
        zonaiDB.sendResetPassword(
          request.collection,
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

  Future<Response?> _send(Request request) async {
    await _ensureRestartedIfRequested();

    final process = await _start();
    if (process == null) {
      if (hasExecutable) {
        logger.debug('Skipping send of request: $request', prefix: _prefix);
      }
      return null;
    }

    final pendingResponse = Completer<(Response, List<MutationRequest>)>();
    _pendingResponses[request.id] = pendingResponse;

    process.stdin.writeln(jsonEncode(request.toJson()));

    try {
      final (response, muts) = await pendingResponse.future.timeout(
        const Duration(seconds: 1),
      );

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
    if (_process case final process?) {
      logger.debug('Killing', prefix: _prefix);
      process.kill();
      _process = null;
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
