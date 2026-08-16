import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../routes/components/admin_invite_rate_limit.dart';
import '../routes/components/oauth_rate_limit.dart';
import '../routes/components/rate_limit.dart';

/// That `RateLimitOperation.adminInvite` is *enforced*, not merely annotated
/// (`docs/admin-invite-design.md` §4 item 9), and that the four `/admin/**`
/// routes are actually reachable and guarded.
///
/// "Enforced" has three separable links and each one has failed silently in
/// this repo or in revali before — the same three
/// `oauth_rate_limit_test.dart` enumerates:
///
/// 1. the guard is **typed** as a [LifecycleComponent], or revali's generator
///    drops it and the route serves unguarded with no error anywhere
///    (known-issues.md #1).
/// 2. the guard is **attached** to the route, which is generated code — read
///    back below from the generated route table.
/// 3. the operation **resolves to a real policy**. A `RateLimitOperation` the
///    policy layer answers `null` for is treated by `RateLimiter.check` as
///    *unlimited*. That link is tested in
///    `libs/zonai_schema/test/src/handlers/rate_limits/admin_invite_rate_limit_policy_test.dart`,
///    where the policy layer lives.
void main() {
  group('the guards are typed so revali generates them', () {
    test('AdminInviteRateLimit is a LifecycleComponent', () {
      expect(
        const AdminInviteRateLimit(),
        isA<LifecycleComponent>(),
        reason:
            'without this the annotation is inert and POST /admin/invites is '
            'unlimited -- see known-issues.md #1',
      );
    });

    test('OAuthInviteStartRateLimit is a LifecycleComponent', () {
      expect(
        const OAuthInviteStartRateLimit(),
        isA<LifecycleComponent>(),
        reason:
            'without this the annotation is inert and the invite-acceptance '
            'start route is unlimited -- see known-issues.md #1',
      );
    });
  });

  group('the invite-acceptance bucket cannot be rotated by a caller', () {
    test('it is a constant, not derived from the request', () {
      // The route's caller-supplied dimensions are `:provider` and `token`.
      // Bucketing on either would let a client rotate it and start from a
      // fresh counter every request -- and for `token` that is precisely the
      // enumeration this limit exists to bound.
      expect(RateLimit.kOAuthInviteStartBucket, 'oauth_admin_invite');
    });

    test('the guard takes only an IP, so there is nothing to rotate', () {
      // A compile-time property asserted as a value: if someone later adds a
      // `@Query('token') String token` to this guard and feeds it to the
      // bucket, this tears.
      const guard = OAuthInviteStartRateLimit();
      expect(guard.check, isA<Future<GuardResult> Function(String)>());
    });

    test('it does not share admin sign-in\'s budget', () {
      // Anyone holding an invite link can reach the acceptance route. Sharing
      // a bucket with `/auth/admin/oauth/start` would let traffic against it
      // exhaust the one flow that must stay reachable.
      expect(
        RateLimit.kOAuthInviteStartBucket,
        isNot(RateLimit.kOAuthAdminStartBucket),
      );
      expect(
        RateLimit.kOAuthInviteStartBucket,
        isNot(RateLimit.kOAuthCallbackBucket),
      );
    });

    test('the bucket key cannot collide with the custom-op key format', () {
      // `RateLimiter.check` asserts the table dimension contains no ':',
      // because ':' separates `table:customOperation` in the shared bucket
      // column.
      expect(RateLimit.kOAuthInviteStartBucket, isNot(contains(':')));
    });
  });

  group('the invite bucket is the caller\'s table, not the invited address', () {
    test('the guard reads a NULLABLE Authorization header, not the body', () {
      // Two properties in one assertion, because one type expression is where
      // both are visible.
      //
      // It takes the header: the invited address is caller-supplied and
      // unbounded, so one fresh counter per address would be no limit at all.
      // The table comes out of the caller's own signed token instead.
      //
      // And it takes it as `String?`: a non-nullable parameter would leave an
      // unauthenticated POST to fail at parameter binding rather than reach
      // the handler's 403. Note the direction -- parameters are contravariant,
      // so a `(String, String)` function does NOT satisfy this matcher while a
      // `(String?, String)` one does. The reverse assertion would pass either
      // way and prove nothing.
      const guard = AdminInviteRateLimit();
      expect(guard.check, isA<Future<GuardResult> Function(String?, String)>());
    });
  });

  group('the generated route table actually carries the routes and guards', () {
    // Reads revali's output rather than trusting the annotations. This is the
    // one link no amount of hand-written Dart can assert, because the wiring
    // is emitted, not written.
    //
    // `.revali/` is gitignored generated output, so it is absent on a clean
    // CI runner and these tests skip there. That is a real gap and it is
    // named rather than hidden: on CI, links 1 and 3 above are what stand
    // between an annotation and an enforced limit.
    final adminRoute = File('.revali/server/routes/__admin_route.dart');
    final authRoute = File('.revali/server/routes/__auth_route.dart');
    final skip = adminRoute.existsSync() && authRoute.existsSync()
        ? null
        : 'no generated server here -- run revali dev --generate-only (this '
              'assertion is skipped, not passed)';

    late final String adminSource = adminRoute.readAsStringSync();
    late final String authSource = authRoute.readAsStringSync();

    test('POST /admin/invites is rate limited', () {
      final block = _routeBlock(adminSource, "'invites'");
      expect(block, contains('AdminInviteRateLimitGuard'));
      expect(block, contains("method: 'POST'"));
    }, skip: skip);

    test('the invite-acceptance start route is rate limited', () {
      final block = _routeBlock(
        authSource,
        "'admin/invite/oauth/start/:provider'",
      );
      expect(block, contains('OAuthInviteStartRateLimitGuard'));
      expect(block, contains("method: 'GET'"));
    }, skip: skip);

    test('every /admin route is behind the IP blacklist', () {
      // `@BlackList()` sits on the controller, so it lands on the `'admin'`
      // parent route and covers all four children. Losing it would leave
      // admin listing and removal with no IP-based abuse protection at all --
      // known-issues.md #1, in the shape it originally happened.
      final block = _routeBlock(adminSource, "'admin'");
      expect(block, contains('BlackListGuard'));
    }, skip: skip);

    test('all four admin routes exist, with the methods they claim', () {
      expect(_routeBlock(adminSource, "'members'"), contains("method: 'GET'"));
      expect(_routeBlock(adminSource, "'invites'"), contains("method: 'POST'"));
      expect(
        _routeBlock(adminSource, "'invites/:email'"),
        contains("method: 'DELETE'"),
      );
      expect(
        _routeBlock(adminSource, "'members/:email'"),
        contains("method: 'DELETE'"),
      );
    }, skip: skip);

    test('every admin route binds the Authorization header', () {
      // The handler decides the 403, and it can only decide it from a header
      // the generated handler actually reads. A route that dropped the
      // binding would pass `null` on every request and refuse everyone --
      // loud. One that bound it under a *different* name would not reach the
      // client's injector at all, which is the quiet half.
      expect(
        "authorization".allMatches(adminSource),
        hasLength(greaterThan(3)),
      );
      for (final path in const [
        "'members'",
        "'invites'",
        "'invites/:email'",
        "'members/:email'",
      ]) {
        expect(
          _routeBlockWithHandler(adminSource, path),
          contains(
            "headers.get(\n              'authorization',\n            )",
          ),
          reason: '$path does not read the authorization header',
        );
      }
    }, skip: skip);

    test('the guard names an operation this build knows about', () {
      // Guards against the reverse of the usual drift: a generated file left
      // over from an older enum.
      expect(
        RateLimitOperation.values.map((e) => e.name),
        contains('adminInvite'),
      );
    });
  });
}

/// The `Route(...)` literal whose first argument is [pathLiteral], up to its
/// `handler:` — the part carrying `guards:` and `method:`.
String _routeBlock(String source, String pathLiteral) {
  final blocks = _matches(
    source,
    RegExp(
      r'Route\(\s*' + RegExp.escape(pathLiteral) + r',(.*?)handler:',
      dotAll: true,
    ),
  );
  expect(blocks, hasLength(1), reason: 'expected exactly one $pathLiteral');
  return blocks.single;
}

/// The whole `Route(...)` literal for [pathLiteral], handler body included.
///
/// Bounded by the next `Route(` or end of file rather than by brace matching,
/// which a regex cannot do. Good enough for "does this handler mention X",
/// which is all it is asked.
String _routeBlockWithHandler(String source, String pathLiteral) {
  final blocks = _matches(
    source,
    RegExp(
      r'Route\(\s*' + RegExp.escape(pathLiteral) + r',(.*?)(?=Route\(|$)',
      dotAll: true,
    ),
  );
  expect(blocks, isNotEmpty, reason: 'no route $pathLiteral');
  return blocks.first;
}

List<String> _matches(String source, RegExp pattern) => [
  for (final match in pattern.allMatches(source)) match.group(1)!,
];
