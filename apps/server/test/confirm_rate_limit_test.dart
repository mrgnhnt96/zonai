import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../routes/components/rate_limit.dart';

/// That `POST /auth/confirm` is *enforced*, not merely policy-able.
///
/// It was neither. `RateLimitOperation.confirm` exists, `confirmPolicy()` is
/// wired in `db_rate_limits.dart`, and the docs list the endpoint with a
/// recommended limit -- but the route carried no `@BodyRateLimit`, so nothing
/// ever invoked any of it and the endpoint was exempt from ALL rate limiting.
/// That is character for character the defect recorded in `auth_controller`
/// for admin auth: "`RateLimit.canContinue` learned to bucket admin bodies,
/// but nothing invoked it here".
///
/// What it costs: every confirm attempt reaches an Argon2 verification
/// (`parts/auth/reset_password.dart`), expensive BY DESIGN, so an
/// unauthenticated caller could force unbounded work with a loop of junk
/// tokens. It is not a guessing risk -- the secret is 32 bytes from
/// `Random.secure()` -- it is CPU exhaustion, on the endpoint a forced
/// password reset depends on to complete inside a 15-minute ticket.
///
/// The links this pins, and the one it cannot: see `oauth_rate_limit_test`,
/// which names the same three. Link 3 (that the operation resolves to a real
/// policy) lives with the policy layer; `confirmPolicy()` returns
/// `defaultPolicy` there, so it is a limit rather than `null`/unlimited.
void main() {
  group('the bucket cannot be rotated by a caller', () {
    test('it is a constant, not derived from the request', () {
      // `VerifyAuthBody` is entirely caller-supplied -- a token, or an email
      // and a code. Bucketing on any of it would let a client start from a
      // fresh counter every request, which is no limit at all.
      expect(RateLimit.kConfirmBucket, '__auth_confirm__');
    });

    test('it cannot collide with a real collection', () {
      // Collection names cannot begin with `__`, which is what makes this
      // key safe to share a column with them.
      expect(RateLimit.kConfirmBucket, startsWith('__'));
    });

    test('it cannot collide with the custom-op key format', () {
      // `RateLimiter.check` separates `table:customOperation` on ':'.
      expect(RateLimit.kConfirmBucket, isNot(contains(':')));
    });
  });

  group('canContinue routes a confirm body to the bucket', () {
    test('it is bucketed, not rejected as an unexpected body type', () async {
      // The half that would otherwise 500 every confirm request. Before the
      // `VerifyAuthBody` arm existed, this body matched nothing in
      // `canContinue`'s switch and fell through to
      // `throw ArgumentError('Unexpected query body type for rate limit')` --
      // so adding the annotation alone would have taken the endpoint from
      // unlimited straight to broken.
      //
      // Asserted as "not an ArgumentError" rather than as a pass, and that is
      // the honest limit of this file: with the arm in place the call gets as
      // far as the limiter and then fails for want of a database, which this
      // file deliberately does not stand up. Remove the arm and it is an
      // ArgumentError again and this tears.
      await expectLater(
        const RateLimit().canContinue(
          VerifyAuthBody.confirmResetPassword(
            token: 'a-token',
            newPassword: 'a-password',
          ),
          '203.0.113.7',
          RateLimitOperation.confirm,
        ),
        throwsA(isNot(isA<ArgumentError>())),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('the generated route table actually carries the guard', () {
    // Reads revali's output rather than trusting the annotation: the wiring
    // is emitted, not written, and an annotation that contributes nothing
    // fails silently (known-issues.md #1).
    //
    // `.revali/` is gitignored, so it is absent on a clean CI runner and this
    // skips there. Named rather than hidden -- exactly as
    // `oauth_rate_limit_test` names it.
    final route = File('.revali/server/routes/__auth_route.dart');
    final skip = route.existsSync()
        ? null
        : 'no generated server here -- run `sip run server gen` (this '
              'assertion is skipped, not passed)';

    late final String source = route.readAsStringSync();

    test('the confirm route is guarded', () {
      final block = _routeBlock(source, "'confirm'");
      expect(block, contains('BodyRateLimitVerifyAuthBodyGuard'));
      expect(block, contains('RateLimitOperation.confirm'));
    }, skip: skip);
  });

  test('the guard names an operation this build knows about', () {
    // The reverse drift: a generated file left over from an older enum.
    expect(RateLimitOperation.values.map((e) => e.name), contains('confirm'));
  });
}

/// The `Route(...)` literal whose first argument is [pathLiteral].
String _routeBlock(String source, String pathLiteral) {
  final pattern = RegExp(
    r'Route\(\s*' + RegExp.escape(pathLiteral) + r',(.*?)handler:',
    dotAll: true,
  );
  final matches = pattern.allMatches(source).toList();
  expect(matches, hasLength(1), reason: 'expected exactly one $pathLiteral');
  return matches.single.group(1)!;
}
