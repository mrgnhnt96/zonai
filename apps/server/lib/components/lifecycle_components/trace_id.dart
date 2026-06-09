import 'package:raindrop/raindrop.dart' hide migrate, Query, Delete, Logger;
import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger;
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/internal/tables/logs_table.dart';
import 'photo_view_headers.dart';

const _errorSummaryMaxLength = 120;

/// A short, human-readable label for grouping errors in logs and dashboards.
String _errorSummary(Object error) => _errorSummaryFromText(error.toString(), fallback: error.runtimeType.toString());

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

  WrapperResult wrap(Context context, NextResponse next) {
    final _logger = logger;
    final _trace = switch (context.request.headers.get('x-trace-id')) {
      null => TraceId.generate(),
      final String s => TraceId(s),
    };

    final callback = (LogDetails details) async {
      if (details.level != .request && details.level != .trace && details.level < .info) return;
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
        ),
      ]);
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
            '${context.request.method} ${context.request.uri}',
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
