import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return const AppConfig(
    appName: 'Zonai Stress Fixture',
    // >= 32 chars because AppConfig.validate requires a 256-bit key for HS256
    // (app_config.dart:189). These are FIXTURE values in a local load-test app that
    // is wiped every run -- they are padded to clear the floor, not to be secret.
    passwordSecret: 'stress-fixture-password-pepper-not-secret',
    jwtSecret: 'stress-fixture-jwt-secret-not-secret',
    baseUrl: 'http://localhost:8099',
  );
}
