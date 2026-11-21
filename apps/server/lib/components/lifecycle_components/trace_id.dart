import 'dart:async';

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger;
import 'package:zonai/src/utils/log_persistence.dart';
import 'photo_view_headers.dart';

const _errorSummaryMaxLength = 120;

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
  'codeVerifier',
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

    final callback = (LogDetails details) => unawaited(
      persistLogLine(details, traceId: _trace.value, isAdmin: isAdminRequest),
    );

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
