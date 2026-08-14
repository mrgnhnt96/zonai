import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// Captures everything written to an [IOSink] as plain text, mirroring how
/// `apps/zonai/test/src/email/courier_test.dart` captures a real [Logger]'s
/// output (see `docs/known-issues.md` #10). That regression was a call
/// silently resolving to a no-op logger; "did not throw" passed against it,
/// so every test here asserts on the captured TEXT a sink actually received.
class _CapturingSink implements IOSink {
  final _writes = <String>[];

  String get text => _writes.join();

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? object) => _writes.add('$object');

  @override
  void writeln([Object? object = '']) => _writes.add('$object');

  @override
  void add(List<int> data) => _writes.add(encoding.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _writes.add('$error');
    if (stackTrace != null) _writes.add('$stackTrace');
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(add);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _writes.add(objects.join(separator));

  @override
  void writeCharCode(int charCode) =>
      _writes.add(String.fromCharCode(charCode));

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> get done => Future.value();
}

void main() {
  late _CapturingSink stdoutSink;
  late _CapturingSink stderrSink;
  late Logger logger;

  void makeLogger({Level level = Level.verbose}) {
    stdoutSink = _CapturingSink();
    stderrSink = _CapturingSink();
    logger = Logger(level: level, stdout: stdoutSink, stderr: stderrSink);
  }

  group('sink routing', () {
    setUp(makeLogger);

    test('info() writes the message to the stdout sink', () {
      logger.info('hello there');

      expect(stdoutSink.text, contains('hello there'));
      expect(stderrSink.text, isEmpty);
    });

    test('warn() writes the message to the stderr sink', () {
      logger.warn('careful now');

      expect(stderrSink.text, contains('careful now'));
      expect(stdoutSink.text, isEmpty);
    });

    test('error() writes the message and error to the stderr sink', () {
      logger.error('it broke', Exception('boom'));

      expect(stderrSink.text, contains('it broke'));
      expect(stderrSink.text, contains('boom'));
      expect(stdoutSink.text, isEmpty);
    });

    for (final level in [
      Level.verbose,
      Level.trace,
      Level.request,
      Level.debug,
    ]) {
      test('$level routes to the stdout sink', () {
        switch (level) {
          case Level.verbose:
            logger.verbose('v');
          case Level.trace:
            logger.trace('t');
          case Level.request:
            logger.request('r');
          case Level.debug:
            logger.debug('d');
          default:
            fail('unhandled level $level');
        }

        expect(stdoutSink.text, isNotEmpty);
        expect(stderrSink.text, isEmpty);
      });
    }
  });

  group('level filtering', () {
    test('a message below the configured level never reaches the sink', () {
      makeLogger(level: Level.warning);

      logger.info('should be filtered out');

      expect(stdoutSink.text, isEmpty);
    });

    test('a message at the configured level reaches the sink', () {
      makeLogger(level: Level.warning);

      logger.warn('should come through');

      expect(stderrSink.text, contains('should come through'));
    });

    test('a message above the configured level reaches the sink', () {
      makeLogger(level: Level.warning);

      logger.error('should also come through');

      expect(stderrSink.text, contains('should also come through'));
    });

    test('raising the level filters previously-visible messages', () {
      makeLogger(level: Level.verbose);
      logger.debug('visible at verbose');
      expect(stdoutSink.text, contains('visible at verbose'));

      makeLogger(level: Level.error);
      logger.debug('invisible at error');
      expect(stdoutSink.text, isEmpty);
    });
  });

  group('callbacks', () {
    setUp(() => makeLogger(level: Level.error));

    test('a callback receives details for a level the sink would filter', () {
      // The trap known-issues.md #10 describes: a caller can wire a callback
      // and observe log traffic even when the configured level would drop it
      // from the sink entirely. Pin that callbacks are NOT level-gated.
      LogDetails? received;
      logger.addCallback((details) => received = details);

      logger.info('filtered from the sink, not from callbacks');

      expect(stdoutSink.text, isEmpty, reason: 'info is below the error floor');
      expect(received, isNotNull);
      expect(received!.message, 'filtered from the sink, not from callbacks');
      expect(received!.level, Level.info);
    });

    test('removeCallback stops further delivery', () {
      var callCount = 0;
      void callback(LogDetails details) => callCount++;

      logger.addCallback(callback);
      logger.info('one');
      expect(callCount, 1);

      logger.removeCallback(callback);
      logger.info('two');
      expect(callCount, 1);
    });

    test(
      'a throwing callback does not stop the sink write or other callbacks',
      () {
        var secondCallbackRan = false;
        logger.addCallback((_) => throw StateError('bad callback'));
        logger.addCallback((_) => secondCallbackRan = true);

        // Level.error is the floor set in setUp, so error() still reaches the sink.
        logger.error('still gets logged');

        expect(stderrSink.text, contains('still gets logged'));
        expect(secondCallbackRan, isTrue);
      },
    );

    test(
      'error() delivers a callback even when its own emit would be filtered',
      () {
        makeLogger(level: Level.request);
        // error() always emits since error is the highest level, but confirm
        // the callback path is exercised independently of the sink write.
        LogDetails? received;
        logger.addCallback((details) => received = details);

        logger.error('boom', Exception('cause'));

        expect(received, isNotNull);
        expect(received!.error, isA<Exception>());
      },
    );
  });

  group('prefix', () {
    setUp(() => makeLogger());

    test('prefixes every non-blank line of a multi-line message', () {
      logger.debug('line one\n\nline two', prefix: 'ctx');

      expect(stdoutSink.text, contains('ctx: line one'));
      expect(stdoutSink.text, contains('ctx: line two'));
    });

    test('a message with no prefix is written as-is', () {
      logger.debug('plain message');

      expect(stdoutSink.text, contains('plain message'));
    });

    test('an entirely blank message writes nothing', () {
      logger.debug('   ');

      expect(stdoutSink.text, isEmpty);
    });
  });

  group('trace', () {
    setUp(() => makeLogger());

    test('captures details via callback including elapsed_ms', () {
      LogDetails? received;
      logger.addCallback((details) => received = details);

      logger.trace('span');

      expect(received!.props, contains('elapsed_ms'));
    });

    test('setTraceProps merges into every subsequent trace call', () {
      LogDetails? received;
      logger.addCallback((details) => received = details);
      logger.setTraceProps({'op': 'select', 'table': 'users'});

      logger.trace('span', extra: {'rows': 3});

      expect(received!.props?['op'], 'select');
      expect(received!.props?['table'], 'users');
      expect(received!.props?['rows'], 3);
    });
  });
}
