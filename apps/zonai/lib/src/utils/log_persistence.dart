import 'dart:async';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger;
import 'package:zonai_schema/src/internal/tables/logs_table.dart'
    show LogEntry, logs;

/// Writes one row to the `_log` table.
typedef LogEntryWriter = Future<void> Function(LogEntry entry);

Future<void> _insertLogEntry(LogEntry entry) async {
  final db = await zonaiDB.open();
  await db.insert(into: logs).values([entry]);
}

/// Whether the most recent attempt to persist a log row failed.
///
/// Latched so a *persistent* condition -- a full volume, a page cap on the
/// log database -- is reported once rather than on every line, and re-armed
/// by the next success so a recurring-but-intermittent problem is not
/// silenced forever by its first occurrence.
bool _logPersistenceFailing = false;

/// Announces that log records have stopped reaching the database.
///
/// Written straight to stderr, and deliberately **not** through `logger`:
/// this runs *from inside* a logger callback, so logging it would re-enter
/// the same callback, fail the same way, and recurse.
///
/// Worth the awkwardness because of how this fails otherwise. A logger
/// callback is a `void Function(LogDetails)`, so the Future of an async write
/// is discarded at the call site (`Logger._log`) and its `try`/`catch` --
/// which only guards a *synchronous* throw -- never sees the error. Measured
/// rather than assumed (see `test/src/logger_async_callback_test.dart`): the
/// error resurfaces as an **unhandled asynchronous error** in whatever zone
/// the line was logged from, once per failed write, carrying nothing that
/// ties it back to logging.
///
/// So the choice is between an unhandled error per line and one deduplicated
/// sentence that says what stopped working. Nothing upstream would otherwise
/// notice that the log table had stopped accepting rows.
void _reportLogPersistenceFailure(Object error) {
  if (_logPersistenceFailing) return;
  _logPersistenceFailing = true;
  stderr.writeln(
    '[ZONAI] Log records are no longer being written to the database: '
    '$error\n'
    '        The server is still serving requests and still printing to the '
    'console, but the dashboard\'s log view will show nothing new until this '
    'clears. Further failures will not be repeated until one succeeds.',
  );
}

/// Writes [details] to `_log`, tagged with [traceId].
///
/// Only actionable levels are kept. `.trace` / `.request` were flooding
/// `_log` with ~10 INSERTs per list call on the same SQLite file as app data,
/// amplifying write-lock contention under load without helping operators.
/// The console still gets every line the logger's level allows.
///
/// Never throws: a failed write is reported once on stderr (see
/// [_reportLogPersistenceFailure]) and the line is dropped.
Future<void> persistLogLine(
  LogDetails details, {
  required String traceId,
  bool isAdmin = false,
  LogEntryWriter write = _insertLogEntry,
}) async {
  if (details.level < .info) return;

  try {
    await write(
      LogEntry(
        traceId: traceId,
        level: switch (details.level) {
          .verbose => .verbose,
          .trace => .trace,
          .request => .request,
          .debug => .debug,
          .info => .info,
          .warning => .warning,
          .error => .error,
        },
        message: details.message,
        error: details.error?.toString(),
        props: details.props,
        isAdmin: isAdmin,
      ),
    );
    _logPersistenceFailing = false;
  } catch (e) {
    _reportLogPersistenceFailure(e);
  }
}

/// Writes the lines [root] logs outside a request to `_log`, with an empty
/// trace id since there is no request to tie them to.
///
/// This is what puts cron, worker and other background output in `_log`.
/// Inside a request, the server's `Trace` component binds a logger of its own
/// that writes each line with the request's trace id. The in-process server
/// routes that logger's console output back through [root], so a line that
/// reaches [root] while another logger is bound is skipped rather than
/// written a second time.
void persistUnscopedLogLines(
  Logger root, {
  LogEntryWriter write = _insertLogEntry,
}) {
  root.addCallback((details) {
    final bound = read(loggerProvider, orElse: () => root);
    if (!identical(bound, root)) return;

    unawaited(persistLogLine(details, traceId: '', write: write));
  });
}
