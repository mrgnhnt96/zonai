part of '../message_handler.dart';

final _loggerProvider = create<_Logger>(_Logger._);

/// Falls back to a no-op [_Logger] when read outside a [runScoped] zone
/// (e.g. calling [DbRules.dispatch] directly in a test, without going
/// through [MessageHandler.listen]'s scope) rather than throwing — logging
/// is diagnostic, not load-bearing, so a caller that never set up a scope
/// shouldn't crash on a `logger.warn` any more than it would on an actual
/// no-op logger.
_Logger get logger => read(_loggerProvider, orElse: _Logger._);

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
