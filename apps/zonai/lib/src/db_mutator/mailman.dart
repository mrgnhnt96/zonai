import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../db_mutator/payloads/payloads.dart';
import '../deps/clean_up.dart';
import '../deps/zonai_db.dart';
import '../deps/fs.dart';
import '../deps/logger.dart';
import '../deps/process.dart';
import '../domain/constants.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    hide logger;

class Mailman<S extends Request, R extends Response> {
  Mailman({
    required this.debugName,
    required this.executablePath,
    required R Function(Map<String, dynamic>) fromJson,
  }) : _response = StreamController.broadcast(),
       _request = StreamController.broadcast(),
       _fromJson = fromJson {
    cleanUp.add(dispose);
    _responseSubscription = _response.stream.listen(_handleResponse);
    _requestSubscription = _request.stream.listen(_handleRequest);
  }

  final String debugName;
  final R Function(Map<String, dynamic>) _fromJson;
  final String executablePath;

  io.Process? _process;
  final StreamController<Request> _request;
  late final StreamSubscription<Request> _requestSubscription;
  final StreamController<Response> _response;
  late final StreamSubscription<Response> _responseSubscription;

  final Map<String, Completer<Response>> _pendingResponses = {};

  Future<void> dispose() async {
    kill();
    _response.close();
    _responseSubscription.cancel();
    _request.close();
    _requestSubscription.cancel();
  }

  String get _prefix => '[${debugName.toUpperCase()}_EXE]';

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
            _ when kIsCompiled => null,
            final trace => StackTrace.fromString(trace),
          },
        );

        if (response.stackTrace case final trace? when !kIsCompiled) {
          logger.debug(trace, prefix: _prefix);
        }
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
      response = switch (request) {
        final GetRecordRequest request => await _fetch(request),
        _ => MessageErrorResponse(
          id: request.id,
          message:
              'Invalid worker request: ${request.runtimeType}(${request.path})',
          error: null,
          stackTrace: null,
        ),
      };
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

  void _handleResponse(Response response) {
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

    completer.complete(response);
  }

  bool get isRunning => _process != null;
  bool get hasExecutable => fs.file(executablePath).existsSync();

  Future<Response> _fetch(GetRecordRequest request) async {
    final (error, results) = await zonaiDB.list(
      request.collection,
      ListPayload(
        where: request.where,
        limit: request.limit,
        offset: request.offset,
        // TODO(mrgnhnt): Forward jwt from request (without forwarding it to the worker)
        jwt: null,
      ),
    );

    if (error != null) {
      return MessageErrorResponse(
        id: request.id,
        message: 'Failed to get records',
        error: '$error',
        stackTrace: null,
      );
    }

    return GetRecordResponse(id: request.id, records: results ?? []);
  }

  Future<io.Process?> _start() async {
    if (_process case final process?) {
      return process;
    }

    if (!hasExecutable) {
      logger.verbose('No executable: $executablePath', prefix: _prefix);
      return null;
    }

    logger.debug('Starting | $executablePath', prefix: _prefix);

    final p = _process = await process.start(executablePath, []);
    p.exitCode.whenComplete(() {
      logger.warn('[$_prefix]: Exited');
      _process = null;
      for (final completer in _pendingResponses.values) {
        completer.completeError(Exception('Process killed'));
      }
      _pendingResponses.clear();
    });

    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_listenToMessages);

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
        _response.add(response);

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
        _request.add(request);
      case _:
        logger.error(
          '$_prefix: Unknown path prefix '
          '(expected "${Response.prefix}" or "${Request.prefix}"): '
          '$pathRaw',
        );
    }
  }

  Future<R?> send(S request) async {
    final Response? response;
    try {
      response = await _send(request);
    } on MessageHandlerFailedException {
      rethrow;
    }
    if (response == null) {
      return null;
    }

    if (response is R) {
      return response;
    }

    return _fromJson(response.payload);
  }

  Future<Response?> _send(Request request) async {
    final process = await _start();
    if (process == null) {
      logger.debug('Skipping send of request: $request', prefix: _prefix);
      return null;
    }

    final pendingResponse = Completer<Response>();
    _pendingResponses[request.id] = pendingResponse;

    process.stdin.writeln(jsonEncode(request.toJson()));

    try {
      return await pendingResponse.future.timeout(const Duration(seconds: 1));
    } on MessageHandlerFailedException {
      rethrow;
    } catch (e, stack) {
      _pendingResponses.remove(request.id);
      logger.error('${_prefix} Response never received', e, stack);
    }

    return null;
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
  /// Only should only be called during development,
  /// and should never be called in production
  Future<void> kill() async {
    if (_process case final process?) {
      logger.debug('Killing', prefix: _prefix);
      process.kill();
      _process = null;
    }

    for (final completer in _pendingResponses.values) {
      completer.completeError(Exception('Process killed'));
    }

    _pendingResponses.clear();
  }
}
