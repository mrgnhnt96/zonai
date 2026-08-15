import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger;
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/internal/tables/logs_table.dart';
import 'photo_view_headers.dart';

const _errorSummaryMaxLength = 120;

/// Whether the most recent attempt to persist a log row failed.
///
/// Latched so a *persistent* condition -- a full volume, a page cap on the
/// log database -- is reported once rather than on every request, and
/// re-armed by the next success so a recurring-but-intermittent problem is
/// not silenced forever by its first occurrence.
bool _logPersistenceFailing = false;

/// Announces that log records have stopped reaching the database.
///
/// Written straight to stderr, and deliberately **not** through `logger`:
/// this runs *from inside* a logger callback, so logging it would re-enter
/// the same callback, fail the same way, and recurse.
///
/// Worth the awkwardness because of how this fails otherwise. The callback is
/// registered as a `void Function(LogDetails)` but is `async`, so the Future
/// it returns is discarded at the call site (`Logger._log`) and its
/// `try`/`catch` -- which only guards a *synchronous* throw -- never sees the
/// error. Measured rather than assumed (see
/// `apps/zonai/test/src/logger_async_callback_test.dart`): the error does not
/// vanish, it resurfaces as an **unhandled asynchronous error** in whatever
/// zone the request was running in, once per failed write, carrying nothing
/// that ties it back to logging. It cannot be handled where it happened,
/// because the Future carrying it is already gone.
///
/// So the choice is between an unhandled error per request and one
/// deduplicated sentence that says what stopped working. The response itself
/// is unaffected either way, which is exactly why nothing upstream would
/// otherwise notice that the log table had stopped accepting rows -- the
/// shape of the incident this whole line of work exists because of.
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

/// A short, human-readable label for grouping errors in logs and dashboards.
String _errorSummary(Object error) => _errorSummaryFromText(
  error.toString(),
  fallback: error.runtimeType.toString(),
);

/// Query parameters whose *values* must never appear in a log line.
///
/// Every one of these is a live credential for the few minutes it exists: an
/// OAuth authorization `code` can be exchanged for a session by anyone who
/// reads it, `state` is the single-use handle that binds the exchange, and
/// the token names are what a native client puts on the wire. Design §4
/// item 7 -- "Secrets, codes, tokens and `state` never reach the logger" --
/// is a property of *this* function, because [Trace] logs
/// `context.request.uri` in full on every request.
///
/// That is not a hypothetical: `logger.request` fires at `Level.request`,
/// which is below `info`, so it prints for anyone running the server at
/// `--log verbose`, `--log trace` or `--log request` -- and
/// `sip run playground serve` passes `--log verbose`. Without this,
/// `GET /auth/oauth/callback/google?code=...&state=...` writes both values to
/// the console. (It does *not* reach the `_log` table: the persistence
/// callback drops anything below `info`. Console-only is still a leak --
/// terminals get scrolled back, piped to files and pasted into issues.)
const _redactedQueryParams = {
  'code',
  'state',
  'id_token',
  'access_token',
  'refresh_token',
  'token',
  'secret',
  'code_verifier',
  'client_secret',
};

/// [uri] with the value of every [_redactedQueryParams] key replaced.
///
/// Keys are preserved so a log line still shows the *shape* of the request --
/// which is the whole diagnostic value of logging the URI, and none of the
/// risk. Unknown parameters are left alone; this is a denylist, and it is
/// named as one so the next person adding a credential-bearing query
/// parameter knows it must be added here too.
String redactSensitiveQuery(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri.toString();
  if (!uri.queryParameters.keys.any(_redactedQueryParams.contains)) {
    return uri.toString();
  }

  // queryParametersAll, not queryParameters: a repeated key collapses to its
  // last value in the latter, so rebuilding from it would silently drop
  // duplicates from the logged shape.
  return uri
      .replace(
        queryParameters: {
          for (final entry in uri.queryParametersAll.entries)
            entry.key: _redactedQueryParams.contains(entry.key)
                ? ['<redacted>']
                : entry.value,
        },
      )
      .toString();
}

/// Returns true if the request was made by a human admin (not a cron worker).
Future<bool> _isAdminRequest(Context context) async {
  final authorization = context.request.headers.get('authorization');
  if (authorization == null) return false;
  const prefix = 'Bearer ';
  final token =
      authorization.trim().length >= prefix.length &&
          authorization.trim().toLowerCase().startsWith(prefix.toLowerCase())
      ? authorization.trim().substring(prefix.length).trim()
      : null;
  if (token == null || token.isEmpty) return false;
  try {
    final jwt = await zonaiDB.parseJwtClaimsOnly(token);
    return jwt?.admin.isAdmin == true;
  } on Object {
    return false;
  }
}

String _errorSummaryFromText(String text, {required String fallback}) {
  final line = text.split('\n').first.trim();
  if (line.isEmpty) return fallback;

  final colon = line.indexOf(':');
  final summary = (colon >= 0 ? line.substring(0, colon) : line).trim();
  final label = summary.isEmpty ? line : summary;

  return label.length <= _errorSummaryMaxLength
      ? label
      : '${label.substring(0, _errorSummaryMaxLength - 1)}…';
}

class TraceId {
  TraceId(this.value);
  static TraceId generate() => TraceId(Id.generate());

  final String value;
}

// Learn more about Lifecycle Components at https://www.revali.dev/constructs/revali_server/lifecycle-components/components
class Trace implements LifecycleComponent {
  const Trace();

  Future<Response> wrap(Context context, NextResponse next) async {
    final _logger = logger;
    final _trace = switch (context.request.headers.get('x-trace-id')) {
      null => TraceId.generate(),
      final String s => TraceId(s),
    };

    final isAdminRequest = await _isAdminRequest(context);

    final callback = (LogDetails details) async {
      // Persist only actionable levels. `.trace` / `.request` were flooding
      // `_log` with ~10 INSERTs per list call on the same SQLite file as app
      // data, amplifying write-lock contention under load without helping
      // operators. Console logging still happens via Logger.print.
      if (details.level < .info) return;

      // Guarded because nothing else guards it. This closure's Future is
      // discarded by the caller, so a failure here is not an error anyone
      // sees -- it is silence. See [_reportLogPersistenceFailure].
      try {
        final db = await zonaiDB.open();

        await db.insert(into: logs).values([
          LogEntry(
            traceId: _trace.value,
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
            isAdmin: isAdminRequest,
          ),
        ]);
        _logPersistenceFailing = false;
      } catch (e) {
        _reportLogPersistenceFailure(e);
      }
    };

    return runMergedScopedFuture(
      () async {
        final stopwatch = Stopwatch()..start();
        try {
          final result = await next();
          applyPhotoViewHeaders(context, result);
          stopwatch.stop();
          logger.request(
            '[${result.statusCode}] ${stopwatch.elapsedMilliseconds}ms: '
            '${context.request.method} '
            '${redactSensitiveQuery(context.request.uri)}',
          );
          result.headers.add('x-trace-id', _trace.value);
          return result;
        } catch (e, stackTrace) {
          logger.error(_errorSummary(e), e, stackTrace);
          rethrow;
        }
      },
      override: {
        loggerProvider.overrideWith(
          () => Logger.print(level: _logger.level)..addCallback(callback),
        ),
      },
    );
  }
}
