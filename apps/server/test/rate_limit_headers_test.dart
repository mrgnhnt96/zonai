import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';
import 'package:zonai/src/services/rate_limit_check.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../routes/components/rate_limit.dart';

/// What a rate-limit 429 carries (GitHub issue #32): `Retry-After`, the
/// `X-RateLimit-*` trio, and a JSON body naming the bucket.
///
/// `RateLimit.exceeded` is the single function every 429 in the guard family
/// goes through, so it is tested directly; the last group reads the guard's
/// source to make sure it stays the single function. The limiter's own
/// arithmetic (`resetAt`, `remaining`, the fixed window) is pinned where the
/// database is: `apps/zonai/test/src/services/rate_limiter_test.dart`.
void main() {
  final t0 = DateTime.utc(2026, 9, 1, 12, 0, 0);

  RateLimitCheck refusedAt(
    DateTime resetAt, {
    String table = 'items',
    RateLimitOperation operation = RateLimitOperation.create,
    String? customOperation,
    int limit = 100,
  }) => RateLimitCheck(
    allowed: false,
    table: table,
    operation: operation,
    customOperation: customOperation,
    limit: limit,
    remaining: 0,
    resetAt: resetAt,
  );

  GuardResult exceededAt(DateTime now, RateLimitCheck check) =>
      withClock(Clock.fixed(now), () => RateLimit.exceeded(check));

  Map<String, Object?> bodyOf(GuardResult result) {
    // Round-tripped through JSON, because that is what the client gets: a
    // body that only works as a Dart map is not the contract.
    final encoded = jsonEncode(result.asBlock.body);
    return jsonDecode(encoded) as Map<String, Object?>;
  }

  group('the 429', () {
    test('carries all four headers, lowercase, like revali\'s Throttle', () {
      final result = exceededAt(
        t0,
        refusedAt(t0.add(const Duration(seconds: 42)), limit: 100),
      );

      expect(result.isBlock, isTrue);
      expect(result.asBlock.statusCode, HttpStatus.tooManyRequests);
      expect(result.asBlock.headers, {
        'retry-after': '42',
        'x-ratelimit-limit': '100',
        'x-ratelimit-remaining': '0',
        // 2026-09-01T12:00:42Z as a Unix epoch in whole seconds.
        'x-ratelimit-reset':
            '${t0.add(const Duration(seconds: 42)).millisecondsSinceEpoch ~/ 1000}',
      });
    });

    test(
      'x-ratelimit-reset is epoch seconds in UTC whatever zone resetAt is in',
      () {
        final resetUtc = t0.add(const Duration(seconds: 42));
        final resetLocal = resetUtc.toLocal();

        final fromUtc = exceededAt(t0, refusedAt(resetUtc));
        final fromLocal = exceededAt(t0, refusedAt(resetLocal));

        expect(
          fromLocal.asBlock.headers!['x-ratelimit-reset'],
          fromUtc.asBlock.headers!['x-ratelimit-reset'],
        );
        expect(
          fromUtc.asBlock.headers!['x-ratelimit-reset'],
          '${resetUtc.millisecondsSinceEpoch ~/ 1000}',
        );
      },
    );

    test('the body is JSON naming the collection and operation', () {
      final result = exceededAt(
        t0,
        refusedAt(
          t0.add(const Duration(seconds: 42)),
          table: 'users',
          operation: RateLimitOperation.signIn,
        ),
      );

      expect(bodyOf(result), {
        'error': 'Rate limit exceeded',
        'collection': 'users',
        'operation': 'signIn',
        'retryAfter': 42,
      });
    });

    test('a custom operation gets its own field, not the table:op key', () {
      final result = exceededAt(
        t0,
        refusedAt(
          t0.add(const Duration(seconds: 42)),
          table: 'items',
          operation: RateLimitOperation.custom,
          customOperation: 'fill',
        ),
      );

      final body = bodyOf(result);
      expect(body['collection'], 'items');
      expect(body['operation'], 'custom');
      expect(body['customOperation'], 'fill');
      expect('${body['collection']}', isNot(contains(':')));
    });

    test('an unvalidated custom operation has no customOperation field', () {
      // `ZONAI_FORCE_WORKERS=1` drops the name and buckets per table; the
      // body must not invent one.
      final result = exceededAt(
        t0,
        refusedAt(
          t0.add(const Duration(seconds: 42)),
          operation: RateLimitOperation.custom,
        ),
      );

      expect(bodyOf(result), isNot(contains('customOperation')));
    });
  });

  group('retry-after', () {
    test('is rounded UP to whole seconds', () {
      // 41.2s left: telling the client 41 would have it retry 800ms into
      // the same closed window.
      final result = exceededAt(
        t0,
        refusedAt(t0.add(const Duration(seconds: 41, milliseconds: 200))),
      );

      expect(result.asBlock.headers!['retry-after'], '42');
      expect(bodyOf(result)['retryAfter'], 42);
    });

    test('is never 0 when less than a second remains', () {
      final result = exceededAt(
        t0,
        refusedAt(t0.add(const Duration(milliseconds: 300))),
      );

      expect(result.asBlock.headers!['retry-after'], '1');
      expect(bodyOf(result)['retryAfter'], 1);
    });

    test('is never 0 even when the reset instant has already passed', () {
      // A refusal computed a moment before the window ended, delivered a
      // moment after. `Retry-After: 0` (or a negative) is still an
      // instruction to retry into a window that may not have rolled yet.
      final result = exceededAt(
        t0.add(const Duration(seconds: 2)),
        refusedAt(t0),
      );

      expect(result.asBlock.headers!['retry-after'], '1');
    });

    test('the header and the body agree', () {
      for (final left in const [
        Duration(milliseconds: 1),
        Duration(seconds: 1),
        Duration(seconds: 59, milliseconds: 999),
        Duration(minutes: 15),
      ]) {
        final result = exceededAt(t0, refusedAt(t0.add(left)));
        expect(
          bodyOf(result)['retryAfter'],
          int.parse(result.asBlock.headers!['retry-after']!),
          reason: 'with $left left',
        );
      }
    });
  });

  group('an unlimited check cannot become a 429', () {
    test('it is refused loudly rather than sent with invented numbers', () {
      // The failure the issue describes is a made-up wait. A bucket with no
      // policy has no window; the helper must not guess one.
      const unlimited = RateLimitCheck.unlimited(
        table: 'items',
        operation: RateLimitOperation.create,
      );
      expect(
        () => withClock(Clock.fixed(t0), () => RateLimit.exceeded(unlimited)),
        throwsA(anyOf(isA<ArgumentError>(), isA<AssertionError>())),
      );
    });
  });

  group('every 429 in the guard goes through the one helper', () {
    // Read as source, the same way the route-table tests read revali's
    // output: the property is "there is exactly one place that builds a
    // 429", and a second `.block(statusCode: 429` anywhere in this file is
    // the drift this exists to catch.
    final source = File('routes/components/rate_limit.dart').readAsStringSync();

    test('the literal 429 block appears exactly once', () {
      expect('statusCode: 429'.allMatches(source), hasLength(1));
    });

    test('the plain-text body is gone', () {
      expect(source, isNot(contains("body: 'Rate limit exceeded'")));
    });
  });
}
