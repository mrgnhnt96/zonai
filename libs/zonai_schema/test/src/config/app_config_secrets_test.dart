import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A value that satisfies every strength rule, so a test asserting one
/// specific rejection is never accidentally passing because of another.
const _strongJwt = 'CqW3nZ8tRv6yLpJ2xHsB5dKm9GfTbNc4';
const _strongPassword = 'Ye7VmQ4rXz2wKtDh6NsLp9JbGc3FvRa8';

AppConfig _config({
  String jwtSecret = _strongJwt,
  String passwordSecret = _strongPassword,
  List<String> previousJwtSecrets = const [],
  List<String> previousPasswordSecrets = const [],
  String appName = 'Test App',
}) {
  return AppConfig(
    appName: appName,
    jwtSecret: jwtSecret,
    passwordSecret: passwordSecret,
    previousJwtSecrets: previousJwtSecrets,
    previousPasswordSecrets: previousPasswordSecrets,
  );
}

Matcher _rejects(String fragment) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(fragment)),
);

void main() {
  group('AppConfig.validate — secret strength', () {
    test('accepts a strong pair', () {
      expect(_config().validate, returnsNormally);
    });

    test('still rejects an empty secret, naming its env var', () {
      expect(
        _config(jwtSecret: '').validate,
        _rejects('jwtSecret is empty — set the JWT_SECRET'),
      );
      expect(
        _config(passwordSecret: '').validate,
        _rejects('passwordSecret is empty — set the PASSWORD_SECRET'),
      );
    });

    // The live finding: `'jwt'` was the real signing key in apps/playground,
    // and guessing it was the whole of the privilege-escalation chain.
    test('rejects the guessable values a real deployment was using', () {
      for (final secret in ['jwt', 'JWT', 'password', 'secret', 'admin']) {
        expect(
          _config(jwtSecret: secret).validate,
          _rejects('placeholder or well-known value'),
          reason: '$secret must not be accepted as a signing key',
        );
      }
    });

    test('rejects the scaffold placeholders, however they are padded', () {
      for (final secret in [
        'change-me-jwt-secret',
        'change-me-jwt-secret-but-long-enough-to-pass-length',
        'CHANGE-ME-JWT-SECRET-PADDED-OUT-TO-BE-LONG',
        'replace-with-a-real-secret-of-sufficient-length',
        'my-placeholder-value-padded-out-to-thirty-two',
      ]) {
        expect(
          _config(jwtSecret: secret).validate,
          _rejects('placeholder or well-known value'),
          reason: '$secret must not be accepted as a signing key',
        );
      }
    });

    test(
      'requires at least 32 characters, since HS256 signs with 256 bits',
      () {
        expect(AppConfig.minSecretLength, 32);
        expect(
          _config(jwtSecret: 'Rk4TmVz9XqBn2wLd').validate,
          _rejects('jwtSecret is 16 characters; at least 32 are required'),
        );
        // Exactly at the boundary is fine.
        expect(
          _config(jwtSecret: 'Rk4TmVz9XqBn2wLdYs7JpHc5NfGb3Qt6').validate,
          returnsNormally,
        );
      },
    );

    test('rejects a long secret that is not actually random', () {
      // Long enough, but eight repeats of four characters.
      expect(
        _config(jwtSecret: 'abcd' * 12).validate,
        _rejects('too few distinct characters'),
      );
      expect(
        _config(jwtSecret: 'a' * 64).validate,
        _rejects('too few distinct characters'),
      );
    });

    test('rejects reusing one value for both secrets', () {
      expect(
        _config(jwtSecret: _strongJwt, passwordSecret: _strongJwt).validate,
        _rejects('must not be the same value'),
      );
    });

    test('rejects a rotation that retires a secret to itself', () {
      expect(
        _config(previousJwtSecrets: const [_strongJwt]).validate,
        _rejects('previousJwtSecrets must not contain the active jwtSecret'),
      );
      expect(
        _config(previousPasswordSecrets: const [_strongPassword]).validate,
        _rejects(
          'previousPasswordSecrets must not contain the active passwordSecret',
        ),
      );
    });

    test('reports every problem at once, not just the first', () {
      expect(
        _config(
          appName: '',
          jwtSecret: 'jwt',
          passwordSecret: 'short',
        ).validate,
        allOf(
          _rejects('appName is empty'),
          _rejects('jwtSecret is a placeholder'),
          _rejects('passwordSecret is 5 characters'),
        ),
      );
    });
  });

  group('AppConfig.withSecretsFromEnvironment', () {
    test('the environment beats the compiled-in value', () {
      final resolved = _config().withSecretsFromEnvironment(const {
        'JWT_SECRET': 'Wq8WnZ4tRv6yLpJ2xHsB5dKm9GfTbNc4',
        'PASSWORD_SECRET': 'Xe3VmQ4rXz2wKtDh6NsLp9JbGc3FvRa8',
      });

      expect(resolved.jwtSecret, 'Wq8WnZ4tRv6yLpJ2xHsB5dKm9GfTbNc4');
      expect(resolved.passwordSecret, 'Xe3VmQ4rXz2wKtDh6NsLp9JbGc3FvRa8');
    });

    test('an absent variable leaves the compiled-in value alone', () {
      final resolved = _config().withSecretsFromEnvironment(const {});

      expect(resolved.jwtSecret, _strongJwt);
      expect(resolved.passwordSecret, _strongPassword);
    });

    // A wrapper script that expands an unset variable to `''` must not be able
    // to blank out a working config -- that would turn a typo into an outage,
    // or worse, into a config that fails validation at 3am on a redeploy.
    test('an empty or whitespace value is ignored, not applied', () {
      final resolved = _config().withSecretsFromEnvironment(const {
        'JWT_SECRET': '',
        'PASSWORD_SECRET': '   ',
      });

      expect(resolved.jwtSecret, _strongJwt);
      expect(resolved.passwordSecret, _strongPassword);
    });

    test('previous secrets come through as a comma-separated list', () {
      final resolved = _config().withSecretsFromEnvironment(const {
        'PREVIOUS_JWT_SECRETS': 'old-one , old-two,',
      });

      expect(resolved.previousJwtSecrets, ['old-one', 'old-two']);
      expect(resolved.previousPasswordSecrets, isEmpty);
    });

    test('everything else is carried over untouched', () {
      final config = AppConfig(
        appName: 'Carried',
        jwtSecret: _strongJwt,
        passwordSecret: _strongPassword,
        baseUrl: 'https://example.test',
        jwtExpiresIn: const Duration(minutes: 7),
      );

      final resolved = config.withSecretsFromEnvironment(const {
        'JWT_SECRET': 'Wq8WnZ4tRv6yLpJ2xHsB5dKm9GfTbNc4',
      });

      expect(resolved.appName, 'Carried');
      expect(resolved.baseUrl, 'https://example.test');
      expect(resolved.jwtExpiresIn, const Duration(minutes: 7));
      expect(resolved.passwordSecret, _strongPassword);
    });
  });

  group('AppConfig.jwtExpiresIn', () {
    // 14 days was the default; a token that cannot be withdrawn for a
    // fortnight is the "stale role" half of the finding.
    test('defaults to 24 hours', () {
      expect(_config().jwtExpiresIn, const Duration(hours: 24));
      expect(
        AppConfig.fromJson({
          'appName': 'x',
          'jwtSecret': _strongJwt,
          'passwordSecret': _strongPassword,
        }).jwtExpiresIn,
        const Duration(hours: 24),
      );
    });

    test('an explicit value still wins', () {
      expect(
        AppConfig.fromJson({
          'appName': 'x',
          'jwtSecret': _strongJwt,
          'passwordSecret': _strongPassword,
          'jwtExpiresIn': 300,
        }).jwtExpiresIn,
        const Duration(minutes: 5),
      );
    });
  });
}
