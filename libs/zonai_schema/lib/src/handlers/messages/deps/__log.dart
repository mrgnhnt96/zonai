part of '../message_handler.dart';

final _loggerProvider = create<_Logger>(_Logger._);

_Logger get logger => read(_loggerProvider);

class _Logger {
  _Logger(this._log);
  _Logger._() : _log = _noop;

  static void _noop(
    String message, {
    required DebugLevel level,
    Map<String, dynamic>? properties,
    String? stackTrace,
    String? error,
  }) {}

  final void Function(
    String message, {
    required DebugLevel level,
    Map<String, dynamic>? properties,
    String? stackTrace,
    String? error,
  })
  _log;

  void debug(String message, {Map<String, dynamic>? properties}) {
    _log(message, level: .debug, properties: properties);
  }

  void info(String message, {Map<String, dynamic>? properties}) {
    _log(message, level: .info, properties: properties);
  }

  void warn(String message, {Map<String, dynamic>? properties}) {
    _log(message, level: .warn, properties: properties);
  }

  void error(
    String message, {
    String? error,
    String? stackTrace,
    Map<String, dynamic>? properties,
  }) {
    _log(
      message,
      level: .error,
      properties: properties,
      stackTrace: stackTrace,
      error: error,
    );
  }
}
