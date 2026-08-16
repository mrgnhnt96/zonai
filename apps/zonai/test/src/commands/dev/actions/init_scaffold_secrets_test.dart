import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/init_scaffold.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// `zonai init` used to scaffold `jwtSecret: 'change-me-jwt-secret'`. A
/// placeholder that *works* is a placeholder nobody replaces, and a guessable
/// HS256 key is enough on its own to mint a token for any user.
void main() {
  group('zonai init scaffolds real secrets', () {
    test('the generated config carries no placeholder secret', () {
      final source = initDbConfigDart();

      expect(source, isNot(contains('change-me-jwt-secret')));
      expect(source, isNot(contains('change-me-password-secret')));
    });

    test('each run generates different secrets', () {
      final first = _secretsIn(initDbConfigDart());
      final second = _secretsIn(initDbConfigDart());

      expect(
        first.jwt,
        isNot(second.jwt),
        reason: 'two projects must not share a signing key',
      );
      expect(first.password, isNot(second.password));
      expect(
        first.jwt,
        isNot(first.password),
        reason: 'the two secrets in one project must differ from each other',
      );
    });

    // The check that matters: the scaffold must produce something the
    // strength rules accept, or `zonai init` would produce a project that
    // refuses to start.
    test('the generated secrets satisfy AppConfig.validate', () {
      final secrets = _secretsIn(initDbConfigDart());

      expect(
        AppConfig(
          appName: 'Scaffolded',
          jwtSecret: secrets.jwt,
          passwordSecret: secrets.password,
        ).validate,
        returnsNormally,
      );
    });

    test('generateSecret is long and high-entropy on its own', () {
      final secret = generateSecret();

      expect(secret.length, greaterThanOrEqualTo(AppConfig.minSecretLength));
      expect(secret.split('').toSet().length, greaterThan(8));
      expect(
        secret,
        isNot(contains('=')),
        reason: 'base64url padding would be noise in a config literal',
      );
    });
  });
}

({String jwt, String password}) _secretsIn(String source) {
  String read(String field) {
    final match = RegExp("$field: '([^']+)'").firstMatch(source);
    expect(
      match,
      isNotNull,
      reason: '$field must be a literal in the scaffold',
    );
    return match!.group(1)!;
  }

  return (jwt: read('jwtSecret'), password: read('passwordSecret'));
}
