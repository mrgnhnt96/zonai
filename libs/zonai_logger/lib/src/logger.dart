import 'dart:io' as io;

import 'package:zonai_logger/src/print_sink.dart';

import 'level.dart';

class LogDetails {
  const LogDetails({
    required this.message,
    required this.level,
    this.error,
    this.stackTrace,
    this.props,
  });

  final String message;
  final Level level;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? props;
}

/// Console-oriented logger with optional ANSI styling.

class Logger {
  Logger({this.level = Level.info, io.IOSink? stdout, io.IOSink? stderr})
    : _stdout = stdout ?? io.stdout,
      _stderr = stderr ?? io.stderr {
    _stopwatch.start();
  }
  Logger.print({this.level = Level.info})
    : _stdout = PrintSink(),
      _stderr = PrintSink() {
    _stopwatch.start();
  }

  /// Minimum level to print. Messages at this level or higher are shown.
  final Level level;

  final io.IOSink _stdout;
  final io.IOSink _stderr;

  final List<void Function(LogDetails)> _callbacks = [];
  final Stopwatch _stopwatch = Stopwatch();
  final Map<String, String> _traceProps = {};

  /// Sets context props included in every [trace] call (e.g. op, table).
  void setTraceProps(Map<String, String> props) {
    _traceProps
      ..clear()
      ..addAll(props);
  }

  bool _emit(Level messageLevel) => messageLevel >= level;

  void verbose(String message, {String? prefix}) =>
      _log(Level.verbose, message, _stdout, _dim, prefix: prefix);

  void trace(String message, {Map<String, dynamic>? extra, String? prefix}) {
    final props = <String, dynamic>{
      'elapsed_ms': _stopwatch.elapsedMilliseconds,
      ..._traceProps,
      if (extra != null) ...extra,
    };
    _log(Level.trace, message, _stdout, _dim, prefix: prefix, props: props);
  }

  void request(String message, {String? prefix}) =>
      _log(Level.request, message, _stdout, _dim, prefix: prefix);
  void debug(String message, {String? prefix}) =>
      _log(Level.debug, message, _stdout, _dim, prefix: prefix);
  void info(String message) => _log(Level.info, message, _stdout, null);
  void warn(String message, {String? prefix}) =>
      _log(Level.warning, message, _stderr, _yellow, prefix: prefix);

  void _err(
    String message, [
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? props,
  ]) {
    final details = LogDetails(
      message: message,
      level: Level.error,
      error: error,
      stackTrace: stackTrace,
      props: props,
    );

    for (final callback in _callbacks) {
      try {
        callback(details);
      } catch (_) {}
    }

    if (!_emit(.error)) return;

    final buffer = StringBuffer();
    if (error != null) {
      buffer.writeln();
      buffer.writeln(error);
    }

    buffer.writeln(message);

    if (stackTrace != null &&
        !const bool.fromEnvironment('__ZONAI_COMPILED__')) {
      buffer.writeln('---');
      buffer.writeln(stackTrace);
    }

    _writeLine(_stderr, buffer.toString(), _red);
  }

  /// Alias for [err] for call sites that prefer `error`.
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _err(message, error, stackTrace);

  void _log(
    Level messageLevel,
    String message,
    io.IOSink sink,
    String Function(String)? style, {
    String? prefix,
    Map<String, dynamic>? props,
  }) {
    final details = LogDetails(
      message: switch (prefix) {
        null => message,
        final p => '$p: $message',
      },
      level: messageLevel,
      props: props,
    );
    for (final callback in _callbacks) {
      try {
        callback(details);
      } catch (_) {}
    }

    if (!_emit(messageLevel)) return;
    if (prefix != null) {
      for (final line in message.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        _writeLine(sink, '$prefix: $trimmed', style);
      }
    } else {
      final trimmed = message.trim();
      if (trimmed.isEmpty) return;
      _writeLine(sink, trimmed, style);
    }
  }

  void _writeLine(io.IOSink sink, String text, String Function(String)? style) {
    final line = style != null && _supportsAnsi(sink) ? style(text) : text;
    sink.writeln(line);
  }

  bool _supportsAnsi(io.IOSink sink) {
    if (identical(sink, io.stdout)) return io.stdout.hasTerminal;
    if (identical(sink, io.stderr)) return io.stderr.hasTerminal;
    return false;
  }

  void addCallback(void Function(LogDetails) callback) {
    _callbacks.add(callback);
  }

  void removeCallback(void Function(LogDetails) callback) {
    _callbacks.remove(callback);
  }

  String _dim(String s) => '\x1B[90m$s\x1B[0m';

  String _yellow(String s) => '\x1B[33m$s\x1B[0m';

  String _red(String s) => '\x1B[31m$s\x1B[0m';
}
