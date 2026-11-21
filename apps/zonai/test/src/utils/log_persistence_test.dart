import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/utils/log_persistence.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/internal/tables/logs_table.dart' show LogEntry;

void main() {
  late List<LogEntry> written;

  Future<void> write(LogEntry entry) async => written.add(entry);

  Logger quietLogger() => Logger(
    level: .error,
    stdout: IOSink(_NullSink()),
    stderr: IOSink(_NullSink()),
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() => written = []);

  group('persistUnscopedLogLines', () {
    test(
      'writes a line logged outside any request, with no trace id',
      () async {
        final root = quietLogger();
        persistUnscopedLogLines(root, write: write);

        await runScoped(() async {
          root.warn('[CRON] failed: nightly');
          await settle();
        }, values: {loggerProvider.overrideWith(() => root)});

        expect(written, hasLength(1));
        expect(written.single.message, '[CRON] failed: nightly');
        expect(written.single.traceId, isEmpty);
        expect(written.single.isAdmin, isFalse);
      },
    );

    test('writes a line even when no logger is bound in scope', () async {
      final root = quietLogger();
      persistUnscopedLogLines(root, write: write);

      root.info('[CRON] started: nightly');
      await settle();

      expect(written.map((e) => e.message), ['[CRON] started: nightly']);
    });

    test('skips lines below info', () async {
      final root = Logger(
        level: .verbose,
        stdout: IOSink(_NullSink()),
        stderr: IOSink(_NullSink()),
      );
      persistUnscopedLogLines(root, write: write);

      root
        ..verbose('v')
        ..trace('t')
        ..request('r')
        ..debug('d');
      await settle();

      expect(written, isEmpty);
    });

    test(
      'skips a line that reaches it while a request logger is bound',
      () async {
        final root = quietLogger();
        persistUnscopedLogLines(root, write: write);
        final requestLogger = quietLogger();

        await runScoped(() async {
          await runScoped(() async {
            root.info('[200] 3ms: GET /db/posts');
            await settle();
          }, values: {loggerProvider.overrideWith(() => requestLogger)});
        }, values: {loggerProvider.overrideWith(() => root)});

        expect(written, isEmpty);
      },
    );

    test('a failed write does not escape as an unhandled error', () async {
      final root = quietLogger();
      persistUnscopedLogLines(
        root,
        write: (_) async => throw StateError('database or disk is full'),
      );

      Object? escaped;
      await runZonedGuarded(() async {
        root.error('Worker crashed');
        await settle();
      }, (error, _) => escaped = error);

      expect(escaped, isNull);
    });
  });

  group('persistLogLine', () {
    test('keeps the trace id, level, error and props', () async {
      await persistLogLine(
        LogDetails(
          message: 'boom',
          level: .error,
          error: StateError('bad'),
          props: {'table': 'posts'},
        ),
        traceId: 'trace-1',
        isAdmin: true,
        write: write,
      );

      final entry = written.single;
      expect(entry.traceId, 'trace-1');
      expect(entry.level.name, 'error');
      expect(entry.message, 'boom');
      expect(entry.error, 'Bad state: bad');
      expect(jsonDecode(entry.props!), {'table': 'posts'});
      expect(entry.isAdmin, isTrue);
    });
  });
}

class _NullSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();
}
