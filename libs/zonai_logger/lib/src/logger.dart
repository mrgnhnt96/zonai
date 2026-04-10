import 'dart:io' as io;

import 'package:io/ansi.dart' show ansiOutputEnabled;

import 'level.dart';

/// Console-oriented logger with optional ANSI styling.
class Logger {
  Logger({this.level = Level.info, io.IOSink? stdout, io.IOSink? stderr})
    : _stdout = stdout ?? io.stdout,
      _stderr = stderr ?? io.stderr;

  /// Minimum level to print. Messages at this level or higher are shown.
  final Level level;

  final io.IOSink _stdout;
  final io.IOSink _stderr;

  bool _emit(Level messageLevel) => messageLevel.index >= level.index;

  bool get _ansi => ansiOutputEnabled;

  void verbose(String message) => _log(Level.verbose, message, _stdout, _dim);

  void trace(String message) => _log(Level.trace, message, _stdout, _dim);

  void debug(String message) => _log(Level.debug, message, _stdout, _dim);

  void info(String message) => _log(Level.info, message, _stdout, null);

  void warn(String message) => _log(Level.warning, message, _stderr, _yellow);

  void err(String message, [Object? error, StackTrace? stackTrace]) {
    if (!_emit(Level.error)) return;
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.writeln();
      buffer.write(error);
    }
    if (stackTrace != null) {
      buffer.writeln();
      buffer.write(stackTrace);
    }
    _writeLine(_stderr, buffer.toString(), _red);
  }

  /// Alias for [err] for call sites that prefer `error`.
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      err(message, error, stackTrace);

  void _log(
    Level messageLevel,
    String message,
    io.IOSink sink,
    String Function(String)? style,
  ) {
    if (!_emit(messageLevel)) return;
    _writeLine(sink, message, style);
  }

  void _writeLine(io.IOSink sink, String text, String Function(String)? style) {
    final line = style != null && _ansi ? style(text) : text;
    sink.writeln(line);
  }

  String _dim(String s) => '\x1B[90m$s\x1B[0m';

  String _yellow(String s) => '\x1B[33m$s\x1B[0m';

  String _red(String s) => '\x1B[31m$s\x1B[0m';
}
