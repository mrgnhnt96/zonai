import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file/local.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/jwt_generator.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  group('CronJwt bearer hardening', () {
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

      await _withTestConfig(() async {
        await expectLater(
          ZonaiDb().parseJwt(token),
          throwsA(
            predicate<StateError>((error) => error.message == 'Invalid JWT'),
          ),
        );
      });
    });

    test('parseJwt returns null when bearer token is absent', () async {
      await _withTestConfig(() async {
        expect(await ZonaiDb().parseJwt(null), isNull);
      });
    });
  });
}

const _jwtSecret = 'test-jwt-pepper';

const _testConfig = AppConfig(
  applicationName: 'test',
  passwordSecret: 'test-password-pepper',
  jwtSecret: _jwtSecret,
);

final _testSettings = Settings(
  path: 'zonai.yaml',
  migrationsPath: '.zonai/migrations',
  dataPath: '.zonai/data',
  schemasPath: 'lib/src/schemas',
  extensionsPath: 'lib/src/extensions',
  rulesPath: 'lib/src/rules',
  operationsPath: 'lib/src/operations',
  configPath: 'lib/src/config',
  emailTemplatesPath: 'lib/src/email_templates',
  rateLimitPath: 'lib/src/rate_limit',
  cronsPath: 'lib/src/crons',
  imagesPath: '.zonai/data/images',
  buildSettings: BuildSettings.current(),
  version: kVersion,
);

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

Future<T> _withTestConfig<T>(Future<T> Function() body) {
  return runMergedScopedFuture(
    body,
    override: {
      fsProvider.overrideWith(LocalFileSystem.new),
      loggerProvider.overrideWith(() => Logger(level: .error)),
      settingsProvider.overrideWith(() => _testSettings),
      configResolverProvider.overrideWith(
        () => ConfigResolver.fixed(_testConfig),
      ),
      cleanUpProvider,
      executableStopProvider,
    },
  );
}
