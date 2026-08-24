import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/jwt_generator.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../../support/config_worker_fixture.dart';

/// An API token's credential is an opaque `zonai_pat_...` string, never a JWT.
/// The `API_TOKEN` payload exists only so a *resolved* token survives the trip
/// to the rules and operations workers.
///
/// So a **signed** one arriving as a bearer token is the single worst thing
/// that could be accepted here: anyone holding the signing secret -- a leaked
/// `jwtSecret`, or a retired one still sitting in `previousJwtSecrets` on
/// purpose -- could mint themselves an unscoped, never-expiring admin identity
/// with no row in `_api_tokens` to revoke. `CronJwt` and `ProvisioningJwt` are
/// refused for exactly this reason; this is the third sentinel and it is the
/// only one whose payload the attacker also gets to choose the *powers* of.
void main() {
  group('ApiTokenJwt bearer hardening', () {
    late ConfigWorkerFixture fixture;
    late Settings settings;

    /// The payload an attacker would write: everything, forever, admin.
    const overPrivileged = {
      'API_TOKEN': true,
      'tokenId': 'forged123456789_pat',
      'name': 'forged',
      'scope': {
        'tables': ['*'],
        'operations': ['view', 'list', 'create', 'update', 'delete'],
        'admin': true,
        'canEdit': true,
      },
      'claims': <String, Object?>{},
      'user': <String, Object?>{},
    };

    setUpAll(() async {
      fixture = await ConfigWorkerFixture.setUp(
        namePrefix: 'api_token_jwt_auth',
        appName: 'API Token JWT Auth Test',
        passwordSecret: _passwordSecret,
        jwtSecret: _jwtSecret,
      );
      settings = await runMergedScopedFuture(
        () async => Settings.load(fixture.projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );
    });

    tearDownAll(() => fixture.tearDown());

    test('the forged token really is signed, and really is admin', () async {
      // Guards the two tests below from passing for the wrong reason. If the
      // signature stopped verifying, or the payload stopped decoding to an
      // admin identity, they would go green while the hole stayed open.
      final token = _manualJwt(
        jwtSecret: _jwtSecret,
        header: const {'alg': 'HS256', 'typ': 'JWT'},
        payload: overPrivileged,
      );

      final decoded = await JwtGenerator(jwtSecret: _jwtSecret).verify(token);
      expect(decoded, isNotNull);
      expect(Jwt.isApiTokenPayload(decoded!), isTrue);

      final identity = Jwt.fromJson(Map<String, dynamic>.from(decoded));
      expect(identity, isA<ApiTokenJwt>());
      expect(identity.admin.isAdmin, isTrue);
      expect(identity.admin.canEdit, isTrue);
      expect((identity as ApiTokenJwt).neverExpires, isTrue);
      expect(identity.scope.allowsTable('anything'), isTrue);
    });

    test('parseJwt rejects a signed API_TOKEN bearer token', () async {
      final token = _manualJwt(
        jwtSecret: _jwtSecret,
        header: const {'alg': 'HS256', 'typ': 'JWT'},
        payload: overPrivileged,
      );

      await _withTestConfig(settings, () async {
        await expectLater(
          ZonaiDb().parseJwt(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('parseJwtClaimsOnly also rejects it', () async {
      // The path that matters most, because it deliberately skips the
      // revocation lookup: the dashboard's SSR feeds its result to
      // `collectionActions` to decide which controls to render. Without this
      // check a forged token is handed an admin identity here with no
      // database read to fail on.
      final token = _manualJwt(
        jwtSecret: _jwtSecret,
        header: const {'alg': 'HS256', 'typ': 'JWT'},
        payload: overPrivileged,
      );

      await _withTestConfig(settings, () async {
        await expectLater(
          ZonaiDb().parseJwtClaimsOnly(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('a bare API_TOKEN flag is refused just as flatly', () async {
      // No scope, no id -- the minimum an attacker has to type. It must not
      // reach `ApiTokenJwt.fromJson`, which would throw a different error and
      // make "refused" depend on the payload being well-formed.
      final token = _manualJwt(
        jwtSecret: _jwtSecret,
        header: const {'alg': 'HS256', 'typ': 'JWT'},
        payload: const {'API_TOKEN': true},
      );

      await _withTestConfig(settings, () async {
        await expectLater(
          ZonaiDb().parseJwt(token),
          throwsA(isA<InvalidJwtException>()),
        );
        await expectLater(
          ZonaiDb().parseJwtClaimsOnly(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });
  });
}

const _jwtSecret = 'test-jwt-pepper-FlKE4k114F5I3XDPAdliKX6gRqv9u7G';
const _passwordSecret = 'test-password-pepper-97i8yJxnqfGV8neFCbVEk79VyRv7mBw';

/// Matches [JwtGenerator]'s HS256 segments (same base64url / padding rules).
String _manualJwt({
  required String jwtSecret,
  required Map<String, Object?> header,
  required Map<String, Object?> payload,
}) {
  final h = base64Url
      .encode(utf8.encode(jsonEncode(header)))
      .replaceAll('=', '');
  final p = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  final signingInput = '$h.$p';
  final mac = Hmac(sha256, utf8.encode(jwtSecret));
  final digest = mac.convert(utf8.encode(signingInput));
  final sig = base64Url.encode(digest.bytes).replaceAll('=', '');
  return '$signingInput.$sig';
}

Future<T> _withTestConfig<T>(Settings settings, Future<T> Function() body) {
  return runMergedScopedFuture(
    body,
    override: {
      fsProvider.overrideWith(LocalFileSystem.new),
      loggerProvider.overrideWith(() => Logger(level: .error)),
      settingsProvider.overrideWith(() => settings),
      processProvider,
      cleanUpProvider,
      executableStopProvider,
    },
  );
}
