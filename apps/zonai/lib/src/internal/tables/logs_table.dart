import 'dart:convert';

import 'package:zonai_schema/zonai_schema.dart';

class LogEntry {
  LogEntry({
    required this.traceId,
    required this.level,
    required this.message,
    this.error,
    Map<String, dynamic>? props,
  }) : id = LogId.generate(),
       timestamp = .now(),
       props = props != null ? jsonEncode(props) : null;

  LogEntry._({
    required this.id,
    required this.traceId,
    required this.timestamp,
    required this.level,
    required this.message,
    required this.error,
    required this.props,
  });

  final LogId id;
  final String traceId;
  final DateTime timestamp;
  final Level level;
  final String message;
  final String? error;
  final String? props;
}

class LogId implements Id {
  LogId(this.value);
  static LogId generate() => LogId(Id.generate('l'));

  @override
  final String value;
}

/// Severity for log lines. Higher values are more important.
///
/// A [Logger] is configured with a minimum [Level]; messages at that level or
/// higher are emitted.
enum Level {
  verbose,
  trace,
  request,
  debug,
  info,
  warning,
  error;

  const Level();

  static Level? fromString(String? level) {
    return switch (level) {
      'verbose' || 'v' => verbose,
      'trace' || 't' => trace,
      'request' || 'r' => request,
      'debug' || 'd' => debug,
      'info' || 'i' => info,
      'warning' || 'w' => warning,
      'error' || 'e' => error,
      _ => null,
    };
  }
}

class LogsTable extends Table<LogEntry> {
  LogsTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: LogId.new,
        generate: LogId.generate,
      ),
      traceId = $.text('trace_id', (s) => s.traceId),
      timestamp = $.createdAt('timestamp', (s) => s.timestamp),
      level = $.enumerator('level', Level.values, (s) => s.level),
      message = $.text('message', (s) => s.message),
      error = $.text('error', (s) => s.error),
      props = $.text('props', (s) => s.props);

  @override
  LogEntry fromRow(RowReader read) {
    return LogEntry._(
      id: read(id),
      traceId: read(traceId),
      timestamp: read(timestamp),
      level: read(level),
      message: read(message),
      error: read(error),
      props: read(props),
    );
  }

  final IdColumn<LogId> id;
  final TextColumn traceId;
  final DateTimeColumn timestamp;
  final EnumColumn<Level> level;
  final TextColumn message;
  final TextColumn? error;
  final TextColumn? props;
}

final logs = table('_log', LogsTable.new, (table) {
  uniqueIndex('log_id_unique').on(table.id);
  index('log_level_timestamp_index').on(table.level, table.timestamp);
});
