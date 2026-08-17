import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';

import '../routes/apps/dev_app.dart';

/// Pins the CORS policy that replaced `@AllowOrigins.all()`.
///
/// The live behaviour being defended: revali_router reflects the caller's
/// `Origin` into `Access-Control-Allow-Origin` and sets
/// `Access-Control-Allow-Credentials: true` unconditionally
/// (`run_origin_check.dart`). With `{'*'}` as the allow-list every origin
/// matched, so a page on any domain could make credentialed calls here and
/// read the replies.
///
/// What this does *not* cover: the `OPTIONS` preflight, which revali_router
/// answers before any middleware runs. See the note on [Cors].
void main() {
  group('Cors component wiring', () {
    test('is typed as a LifecycleComponent, so it is actually generated', () {
      // Same failure mode as known-issues.md #1: without the `implements`
      // clause `@Cors()` still compiles, codegen still succeeds, and the
      // component contributes nothing at all -- silently.
      expect(
        const Cors(),
        isA<LifecycleComponent>(),
        reason:
            'without this the annotation is inert and every response '
            'keeps the reflected origin and credentials header',
      );
    });
  });

  group('decideCors', () {
    test('grants a loopback origin credentials', () {
      final decision = decideCors('http://localhost:8080');

      expect(decision.allowOrigin, 'http://localhost:8080');
      expect(decision.allowCredentials, isTrue);
    });

    test('grants an operator-configured origin credentials', () {
      final decision = decideCors(
        'https://app.example.com',
        configured: {'https://app.example.com'},
      );

      expect(decision.allowOrigin, 'https://app.example.com');
      expect(decision.allowCredentials, isTrue);
    });

    test('gives a hostile origin no Allow-Origin and no credentials', () {
      // The finding, exactly: `Origin: https://evil.example` came back
      // reflected, with Access-Control-Allow-Credentials: true.
      final decision = decideCors('https://evil.example');

      expect(
        decision.allowOrigin,
        isNull,
        reason:
            'emitting no Allow-Origin is what makes the browser refuse '
            'to hand the response to the page',
      );
      expect(decision.allowCredentials, isFalse);
    });

    test('never pairs a wildcard origin with credentials', () {
      // No Origin header: not a cross-origin browser request. `*` is fine on
      // its own, but `*` plus credentials would be a blanket grant.
      final decision = decideCors(null);

      expect(decision.allowOrigin, '*');
      expect(decision.allowCredentials, isFalse);
    });
  });

  group('isAllowedOrigin', () {
    test('accepts the origins the dashboard is served from', () {
      expect(isAllowedOrigin('http://localhost:8080'), isTrue);
      expect(isAllowedOrigin('http://127.0.0.1:8080'), isTrue);
      expect(isAllowedOrigin('http://[::1]:8080'), isTrue);
      expect(isAllowedOrigin('https://localhost'), isTrue);
    });

    test('rejects a hostile origin', () {
      expect(isAllowedOrigin('https://evil.example'), isFalse);
      expect(isAllowedOrigin('http://evil.example:8080'), isFalse);
    });

    test('is anchored, so a lookalike domain cannot slip through', () {
      // The pattern is matched with hasMatch, a substring test. Unanchored,
      // every one of these would be allowed -- and each is registrable.
      expect(isAllowedOrigin('https://localhost.evil.example'), isFalse);
      expect(isAllowedOrigin('https://evil.example/http://localhost'), isFalse);
      expect(isAllowedOrigin('https://not-localhost:8080'), isFalse);
      expect(isAllowedOrigin('http://127.0.0.1.evil.example'), isFalse);
    });

    test('does not treat the dots in an IP as regex wildcards', () {
      // `\.` written into generated source becomes a bare `.`, which matches
      // any character -- this is the corruption that took the allow-list off
      // the annotation and into a runtime regex.
      expect(isAllowedOrigin('http://127x0x0x1:8080'), isFalse);
    });
  });

  group('parseOrigins', () {
    test('is empty when unset, leaving only the loopback default', () {
      expect(parseOrigins(null), isEmpty);
      expect(parseOrigins('  '), isEmpty);
    });

    test('splits and trims a comma-separated list', () {
      expect(
        parseOrigins('https://app.example.com, https://admin.example.com'),
        {'https://app.example.com', 'https://admin.example.com'},
      );
    });
  });
}
