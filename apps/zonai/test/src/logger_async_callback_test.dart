import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// What [Logger] does with a callback that fails asynchronously.
///
/// The server's log-persistence callback (`apps/server`'s `Trace`) is
/// registered here and writes a row to `_log`. Whether a failed write is
/// visible, fatal, or silent is decided entirely by this dispatch, so it is
/// pinned rather than assumed -- the guard in `Trace` exists *because* of the
/// answer, and would look like defensive noise without it.
void main() {
  test('a callback that throws asynchronously escapes as an unhandled zone '
      'error -- the try/catch around it never sees it', () async {
    final sink = _CapturingSink();
    final logger = Logger(level: .info, stdout: IOSink(sink));

    var callbackRan = false;
    // `addCallback` takes a `void Function(LogDetails)`. An `async` closure
    // satisfies that -- it is a `Future<void> Function(...)`, assignable to
    // it -- and the Future it returns is then dropped on the floor.
    logger.addCallback((details) async {
      callbackRan = true;
      throw StateError('database or disk is full');
    });

    Object? escaped;
    await runZonedGuarded(() async {
      logger.info('a message worth persisting');
      // Let the discarded Future settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (error, _) => escaped = error);

    expect(callbackRan, isTrue, reason: 'the callback has to have run');
    expect(
      escaped,
      isA<StateError>(),
      reason:
          'this is the whole point, and it is worse than it looks. The '
          'error is not thrown to whoever called `logger.info` -- the '
          'Future carrying it was discarded -- so it cannot be handled '
          'where it happened. It resurfaces as an *unhandled* asynchronous '
          'error in whatever zone the request was running in, once per '
          'failed write, with no context tying it back to logging. That is '
          'why the callback in apps/server catches and reports for itself '
          'instead of leaving this to whatever the zone does with it.',
    );

    // And the caller is genuinely unaffected: a failing log write does not
    // take a response down with it, which is the other half of why nothing
    // upstream would ever notice.
    expect(sink.text, contains('a message worth persisting'));
  });

  test(
    'a callback that throws synchronously is swallowed by the logger itself',
    () async {
      final sink = _CapturingSink();
      final logger = Logger(level: .info, stdout: IOSink(sink));

      logger.addCallback((details) => throw StateError('sync failure'));

      Object? escaped;
      await runZonedGuarded(() async {
        logger.info('still logged');
      }, (error, _) => escaped = error);

      expect(
        escaped,
        isNull,
        reason: 'the try/catch in Logger covers this case -- and only this one',
      );
      expect(sink.text, contains('still logged'));
    },
  );
}

class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}
