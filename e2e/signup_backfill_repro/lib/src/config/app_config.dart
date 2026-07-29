import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Signup Backfill E2E',
    passwordSecret: 'e2e-password-pepper',
    jwtSecret: 'e2e-zonai-jwt-secret',
    baseUrl: 'http://localhost:8080',
  );
}
