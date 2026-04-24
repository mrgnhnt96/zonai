import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/process.dart';
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
        logger.debug(response.message);
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
      for (final line in jsonProps.split('\n')) {
        logger.debug('$_prefix: $line');
      }
    }
  }

  void _handleResponse(Response response) {
    switch (response) {
      case DebugResponse():
        _log(response);
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
      logger.debug('$_prefix: Exists');
      return process;
    }

    if (!hasExecutable) {
      logger.debug('$_prefix: No executable: $executablePath');
      return null;
    }

    logger.debug('$_prefix: Starting | $executablePath');

    final p = _process = await process.start(executablePath, []);
    p.exitCode.whenComplete(() {
      logger.debug('$_prefix: Exited');
      _process = null;
      for (final completer in _pendingResponses.values) {
        completer.completeError(Exception('Process killed'));
      }
      _pendingResponses.clear();
    });

    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      event,
    ) {
      final json = jsonDecode(event.trim());

      _response.add(Response.fromJson(json));
    });

    logger.debug('$_prefix: Started');

    return p;
  }

  Future<R?> send(S request) async {
    final response = await _send(request);
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
      logger.debug('$_prefix: Skipping send of request: $request');
      return null;
    }

    process.stdin.writeln(jsonEncode(request));

    final pendingResponse = Completer<Response>();

    _pendingResponses[request.id] = pendingResponse;

    try {
      return await pendingResponse.future.timeout(const Duration(seconds: 1));
    } catch (e) {
      logger.error('Response never received: Error');
      logger.error('$e');
    }

    return null;
  }

  Future<bool> ping() async {
    logger.debug('Pinging $executablePath');
    final response = await _send(RequestPing());
    if (response == null) {
      logger.debug('Failed to ping');
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
      logger.debug('$_prefix: Killing');
      process.kill();
      _process = null;
    }

    for (final completer in _pendingResponses.values) {
      completer.completeError(Exception('Process killed'));
    }

    _pendingResponses.clear();
  }
}
