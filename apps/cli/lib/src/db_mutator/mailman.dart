import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    hide logger;

class Mailman<S extends Request, R extends Response> {
  Mailman({
    required this.debugName,
    required this.executablePath,
    required R Function(Map<String, dynamic>) fromJson,
  }) : _response = StreamController<Response>.broadcast(),
       _fromJson = fromJson {
    cleanUp.add(dispose);
    _responseSubscription = _response.stream.listen(_handleResponse);
  }

  final String debugName;
  final R Function(Map<String, dynamic>) _fromJson;
  final String executablePath;
  io.Process? _process;
  final StreamController<Response> _response;
  late final StreamSubscription<Response> _responseSubscription;

  final Map<String, Completer<Response>> _pendingResponses = {};

  Future<void> dispose() async {
    kill();
    _response.close();
    _responseSubscription.cancel();
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

  void _handleResponse(Response response) {
    if (response is DebugResponse) {
      _log(response);
      return;
    }
    if (response is MessageErrorResponse) {
      final id = response.id;
      final message = response.message;
      final err = response.error;
      final stackTrace = response.stackTrace;
      final completer = _pendingResponses.remove(id);
      if (completer == null) {
        assert(false, 'Received error for unknown request: $id');
        return;
      }
      logger.error(
        '$_prefix $message',
        err,
        stackTrace != null ? StackTrace.fromString(stackTrace) : null,
      );
      completer.completeError(
        MessageHandlerFailedException(
          message,
          cause: err,
          causeStackTrace: stackTrace,
        ),
      );
      return;
    }
    final completer = _pendingResponses.remove(response.id);

    if (completer == null) {
      assert(false, 'Received response for unknown request: ${response.path}');
      return;
    }

    completer.complete(response);
  }

  bool get isRunning => _process != null;
  bool get hasExecutable => fs.file(executablePath).existsSync();

  Future<io.Process?> _start() async {
    if (_process case final process?) {
      logger.debug('Exists', prefix: _prefix);
      return process;
    }

    if (!hasExecutable) {
      logger.debug('No executable: $executablePath', prefix: _prefix);
      return null;
    }

    logger.debug('Starting | $executablePath', prefix: _prefix);

    final p = _process = await process.start(executablePath, []);
    p.exitCode.whenComplete(() {
      logger.debug('Exited', prefix: _prefix);
      _process = null;
      for (final completer in _pendingResponses.values) {
        completer.completeError(Exception('Process killed'));
      }
      _pendingResponses.clear();
    });

    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      event,
    ) {
      try {
        final json = jsonDecode(event.trim()) as Map<String, dynamic>;
        _response.add(Response.fromJson(json));
      } catch (e, stack) {
        logger.error('$_prefix Malformed message on stdout', e, stack);
      }
    });

    logger.debug('Started', prefix: _prefix);

    return p;
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

    process.stdin.writeln(jsonEncode(request));

    final pendingResponse = Completer<Response>();

    _pendingResponses[request.id] = pendingResponse;

    try {
      return await pendingResponse.future.timeout(const Duration(seconds: 1));
    } on MessageHandlerFailedException {
      rethrow;
    } catch (e, stack) {
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
