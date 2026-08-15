import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../routes/components/oauth_rate_limit.dart';
import '../routes/components/rate_limit.dart';

/// That `RateLimitOperation.oauthStart` / `.oauthCallback` are *enforced*,
/// not merely annotated (design §4 item 8).
///
/// "Enforced" has three separable links, and each one has failed silently in
/// this repo or in revali before:
///
/// 1. the guard is **typed** as a [LifecycleComponent], or revali's generator
///    drops it and the route serves unguarded with no error anywhere. That is
///    known-issues.md #1, which left the whole auth surface unprotected;
///    `lifecycle_component_wiring_test.dart` pins the same property for
///    `@BlackList()`.
/// 2. the guard is **attached** to the routes, which is generated code — read
///    back below from the generated route table.
/// 3. the operation **resolves to a real policy**. A `RateLimitOperation` the
///    policy layer answers `null` for is treated by `RateLimiter.check` as
///    *unlimited*, so the annotation, the guard and the wiring can all be
///    perfect and the limit still not exist. That link is tested in
///    `libs/zonai_schema/test/rate_limits/oauth_rate_limit_policy_test.dart`,
///    where the policy layer lives.
void main() {
  group('the guards are typed so revali generates them', () {
    test('OAuthStartRateLimit is a LifecycleComponent', () {
      expect(
        const OAuthStartRateLimit(),
        isA<LifecycleComponent>(),
        reason:
            'without this the annotation is inert and /auth/oauth/start is '
            'unlimited -- see known-issues.md #1',
      );
    });

    test('OAuthCallbackRateLimit is a LifecycleComponent', () {
      expect(
        const OAuthCallbackRateLimit(),
        isA<LifecycleComponent>(),
        reason:
            'without this the annotation is inert and /auth/oauth/callback is '
            'unlimited -- see known-issues.md #1',
      );
    });
  });

  group('the callback bucket cannot be rotated by a caller', () {
    test('it is a constant, not derived from the request', () {
      // The callback's only caller-supplied dimensions are `:provider` and
      // `state`. Bucketing on either would let a client rotate it and start
      // from a fresh counter every request -- the identical bypass
      // `RateLimit.checkCustomOperation` exists to close for `:operation`.
      expect(RateLimit.kOAuthCallbackBucket, 'oauth');
    });

    test('the guard takes only an IP, so there is nothing to rotate', () {
      // A compile-time property, asserted as a value: if someone later adds a
      // `@Param() String provider` to this guard and feeds it to the bucket,
      // this tears.
      const guard = OAuthCallbackRateLimit();
      expect(guard.check, isA<Future<GuardResult> Function(String)>());
    });

    test('the bucket key cannot collide with the custom-op key format', () {
      // `RateLimiter.check` asserts the table dimension contains no ':',
      // because ':' is what separates `table:customOperation` in the shared
      // bucket column.
      expect(RateLimit.kOAuthCallbackBucket, isNot(contains(':')));
    });
  });

  group('the generated route table actually carries the guards', () {
    // Reads revali's output rather than trusting the annotations. This is the
    // one link that no amount of hand-written Dart can assert, because the
    // wiring is emitted, not written.
    //
    // `.revali/` is gitignored generated output, so it is absent on a clean
    // CI runner and these tests skip there. That is a real gap and it is
    // named rather than hidden: on CI, links 1 and 3 above are what stand
    // between an annotation and an enforced limit. Locally, after
    // `sip run server gen`, all three are checked.
    final route = File('.revali/server/routes/__auth_route.dart');
    final skip = route.existsSync()
        ? null
        : 'no generated server here -- run `sip run server gen` (this '
              'assertion is skipped, not passed)';

    late final String source = route.readAsStringSync();

    test('the start route is guarded', () {
      final block = _routeBlock(source, "'oauth/start/:provider'");
      expect(block, contains('OAuthStartRateLimitGuard'));
    }, skip: skip);

    test('the GET callback route is guarded', () {
      final blocks = _routeBlocks(source, "'oauth/callback/:provider'");
      expect(blocks, hasLength(2), reason: 'expected a GET and a POST route');
      for (final block in blocks) {
        expect(block, contains('OAuthCallbackRateLimitGuard'));
      }
    }, skip: skip);

    test(
      'the POST (Apple form_post) callback route exists and is guarded',
      () {
        final blocks = _routeBlocks(source, "'oauth/callback/:provider'");
        expect(blocks.any((b) => b.contains("method: 'POST'")), isTrue);
        expect(blocks.any((b) => b.contains("method: 'GET'")), isTrue);
      },
      skip: skip,
    );

    test('the native flow is guarded too', () {
      final block = _routeBlock(source, "'oauth'");
      expect(block, contains('RateLimitOperation.authenticate'));
    }, skip: skip);

    test('the guard names an operation this build knows about', () {
      // Guards against the reverse of the usual drift: a generated file left
      // over from an older enum.
      expect(
        RateLimitOperation.values.map((e) => e.name),
        containsAll(<String>['oauthStart', 'oauthCallback']),
      );
    });
  });
}

/// The `Route(...)` literal whose first argument is [pathLiteral].
String _routeBlock(String source, String pathLiteral) {
  final blocks = _routeBlocks(source, pathLiteral);
  expect(blocks, hasLength(1), reason: 'expected exactly one $pathLiteral');
  return blocks.single;
}

List<String> _routeBlocks(String source, String pathLiteral) {
  final result = <String>[];
  // `Route(\n  <path>,` -- the generated shape. Everything up to the next
  // `handler:` is the route's own configuration, which is where `guards:` and
  // `method:` live.
  final pattern = RegExp(
    r'Route\(\s*' + RegExp.escape(pathLiteral) + r',(.*?)handler:',
    dotAll: true,
  );
  for (final match in pattern.allMatches(source)) {
    result.add(match.group(1)!);
  }
  return result;
}
