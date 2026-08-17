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

void main() {
  group('CronJwt bearer hardening', () {
    late ConfigWorkerFixture fixture;
    late Settings settings;

    setUpAll(() async {
      fixture = await ConfigWorkerFixture.setUp(
        namePrefix: 'cron_jwt_auth',
        appName: 'Cron JWT Auth Test',
        passwordSecret: _passwordSecret,
        jwtSecret: _jwtSecret,
      );
      settings = await runMergedScopedFuture(
        () async => Settings.load(fixture.projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );
    });

    tearDownAll(() => fixture.tearDown());

    test('signed CRON payload verifies but is forbidden as user JWT', () async {
      final token = _manualJwt(
        jwtSecret: _jwtSecret,
        header: const {'alg': 'HS256', 'typ': 'JWT'},
        payload: const {'CRON': true},
      );

      final decoded = await JwtGenerator(jwtSecret: _jwtSecret).verify(token);
      expect(decoded, isNotNull);
      expect(Jwt.isCronWorkerPayload(decoded!), isTrue);
      expect(Jwt.fromJson(Map<String, dynamic>.from(decoded)), isA<CronJwt>());
    });

    test('parseJwt rejects signed bearer token with CRON payload', () async {
      final token = _manualJwt(
        jwtSecret: _jwtSecret,
        header: const {'alg': 'HS256', 'typ': 'JWT'},
        payload: const {'CRON': true},
      );

      await _withTestConfig(settings, () async {
        await expectLater(
          ZonaiDb().parseJwt(token),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    });

    test('parseJwt returns null when bearer token is absent', () async {
      await _withTestConfig(settings, () async {
        expect(await ZonaiDb().parseJwt(null), isNull);
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
