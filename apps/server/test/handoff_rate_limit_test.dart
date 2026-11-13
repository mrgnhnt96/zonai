import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../routes/components/rate_limit.dart';

/// That `POST /auth/handoff` and `POST /auth/handoff/exchange` are
/// *enforced*, not merely policy-able.
///
/// The three links named in `oauth_rate_limit_test` apply here too. This file
/// pins two of them: that `canContinue` buckets both bodies rather than
/// throwing on an unexpected type, and that the generated route table carries
/// the guards. The third (each operation resolves to a real policy rather
/// than `null`, which means unlimited) lives with the policy layer in
/// `libs/zonai_schema/test/src/handlers/rate_limits/handoff_rate_limit_policy_test.dart`.
void main() {
  group('canContinue routes the handoff bodies to a bucket', () {
    // Asserted as "not an ArgumentError" for the reason given in
    // `confirm_rate_limit_test`: past the switch, the call reaches the
    // limiter and fails for want of a database this file does not stand up.
    // Without the arms it is an ArgumentError and every handoff is a 500.
    test('a create body is bucketed', () async {
      await expectLater(
        const RateLimit().canContinue(
          const HandoffAuthBody(
            table: 'users',
            codeChallenge: 'a-challenge',
            codeChallengeMethod: 'S256',
          ),
          '203.0.113.7',
          RateLimitOperation.handoffCreate,
        ),
        throwsA(isNot(isA<ArgumentError>())),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('an exchange body is bucketed', () async {
      await expectLater(
        const RateLimit().canContinue(
          const ExchangeHandoffAuthBody(
            table: 'users',
            code: 'a-code',
            codeVerifier: 'a-verifier',
          ),
          '203.0.113.7',
          RateLimitOperation.handoffExchange,
        ),
        throwsA(isNot(isA<ArgumentError>())),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('the generated route table actually carries the guards', () {
    // `.revali/` is gitignored, so this skips on a clean CI runner, exactly as
    // `oauth_rate_limit_test` names it.
    final route = File('.revali/server/routes/__auth_route.dart');
    final skip = route.existsSync()
        ? null
        : 'no generated server here -- run `sip run server gen` (this '
              'assertion is skipped, not passed)';

    late final String source = route.readAsStringSync();

    test('creating a code is guarded', () {
      final block = _routeBlock(source, "'handoff'");
      expect(block, contains('BodyRateLimitHandoffAuthBodyGuard'));
      expect(block, contains('RateLimitOperation.handoffCreate'));
    }, skip: skip);

    test('exchanging a code is guarded', () {
      final block = _routeBlock(source, "'handoff/exchange'");
      expect(block, contains('BodyRateLimitExchangeHandoffAuthBodyGuard'));
      expect(block, contains('RateLimitOperation.handoffExchange'));
    }, skip: skip);
  });

  test('the guards name operations this build knows about', () {
    expect(
      RateLimitOperation.values.map((e) => e.name),
      containsAll(<String>['handoffCreate', 'handoffExchange']),
    );
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
