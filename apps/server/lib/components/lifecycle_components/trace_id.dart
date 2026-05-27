import 'package:raindrop/raindrop.dart' hide migrate, Query, Delete, Logger;
import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger;
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/internal/logs_table.dart';

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
      if (details.level != .request && details.level < .info) return;
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
        ),
      ]);
    };

    return runMergedScopedFuture(
      () async {
        final stopwatch = Stopwatch()..start();
        try {
          final result = await next();
          stopwatch.stop();
          logger.request(
            '[${result.statusCode}] ${stopwatch.elapsedMilliseconds}ms: '
            '${context.request.method} ${context.request.uri}',
          );
          result.headers.add('x-trace-id', _trace.value);
          return result;
        } catch (e, stackTrace) {
          logger.error('Uncaught error', e, stackTrace);
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
