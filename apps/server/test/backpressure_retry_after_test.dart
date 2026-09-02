import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';

import '../routes/components/exception_catcher.dart';

/// What a write-backpressure 503 carries: `retry-after`, so a client that hits
/// a full write queue has a number to wait on instead of retrying blind.
///
/// The same defect the 429 had (GitHub issue #32, `rate_limit_headers_test`),
/// with one difference worth pinning: the 429 computes its wait from a window
/// it knows, and this one cannot. The queue drains in tens of milliseconds and
/// the server does not know when a slot frees, so the value is a floor from a
/// single constant, never a prediction -- and never 0.
///
/// `Exceptions` is the catcher revali wires for the whole server; the
/// `LifecycleComponent` check is the same one `admin_invite_rate_limit_test`
/// makes for its guards, because a catcher that is not typed as one is
/// silently dropped by the generator and the exception reaches the client as
/// an unhandled 500 (known-issues.md #1).
void main() {
  const catcher = Exceptions();

  test('the catcher is a LifecycleComponent so revali generates it', () {
    expect(
      catcher,
      isA<LifecycleComponent>(),
      reason:
          'without this the whole catcher is inert and every mapped '
          'exception reaches the client as a 500 -- see known-issues.md #1',
    );
  });

  group('the write-backpressure 503', () {
    final handled = catcher
        .onWriteBackpressure(const WriteBackpressureException())
        .asHandled;

    test('is a 503', () {
      expect(handled.statusCode, HttpStatus.serviceUnavailable);
    });

    test(
      'carries retry-after, lowercase, like the 429 and revali\'s Throttle',
      () {
        expect(handled.headers, containsPair('retry-after', isA<String>()));
        expect(handled.headers!.keys, everyElement(equals('retry-after')));
      },
    );

    test('the value is the one constant, in whole seconds', () {
      expect(
        handled.headers!['retry-after'],
        '$kBackpressureRetryAfterSeconds',
      );
      // Whole seconds is the only unit `Retry-After` has; a fraction is not a
      // valid delay-seconds and a client may parse it as 0.
      expect(int.tryParse(handled.headers!['retry-after']!), isNotNull);
    });

    test('is never 0', () {
      // `Retry-After: 0` is an instruction to retry into the same full queue,
      // which is exactly the blind spin the header exists to stop.
      expect(kBackpressureRetryAfterSeconds, greaterThanOrEqualTo(1));
      expect(
        int.parse(handled.headers!['retry-after']!),
        greaterThanOrEqualTo(1),
      );
    });

    test('keeps the body the client already knew', () {
      expect(handled.body, {
        'error':
            'Server is busy writing; retry shortly (write queue saturated).',
      });
    });
  });

  /// The read gate's refusal had no catcher at all until now, so it fell
  /// through revali's `run_catchers` to `defaultResponses.internalServerError`
  /// -- a 500 with no `retry-after`, for a refusal the server chose. These
  /// pin it to the same answer the write side gives.
  group('the read-backpressure 503', () {
    final handled = catcher
        .onReadBackpressure(const ReadBackpressureException())
        .asHandled;

    test('is a 503, not the 500 it used to fall through to', () {
      expect(handled.statusCode, HttpStatus.serviceUnavailable);
      expect(handled.statusCode, isNot(HttpStatus.internalServerError));
    });

    test('carries retry-after, lowercase, like the write side', () {
      expect(handled.headers, containsPair('retry-after', isA<String>()));
      expect(handled.headers!.keys, everyElement(equals('retry-after')));
    });

    test('the value is the one constant, in whole seconds', () {
      expect(
        handled.headers!['retry-after'],
        '$kBackpressureRetryAfterSeconds',
      );
      expect(int.tryParse(handled.headers!['retry-after']!), isNotNull);
    });

    test('is never 0', () {
      expect(
        int.parse(handled.headers!['retry-after']!),
        greaterThanOrEqualTo(1),
      );
    });

    test('the body is the exception the client can act on', () {
      expect(handled.body, {
        'error':
            'Server is busy reading; retry shortly (read concurrency '
            'saturated).',
      });
    });
  });

  /// One constant, both directions. Two numbers would let the read side drift
  /// from the write side silently, and a client that special-cases one of
  /// them would be wrong about the other.
  test('both directions of backpressure answer identically', () {
    final write = catcher
        .onWriteBackpressure(const WriteBackpressureException())
        .asHandled;
    final read = catcher
        .onReadBackpressure(const ReadBackpressureException())
        .asHandled;

    expect(read.statusCode, write.statusCode);
    expect(read.headers, write.headers);
    // Only the sentence differs -- it names which side is busy.
    expect(read.body, isNot(write.body));
  });
}
