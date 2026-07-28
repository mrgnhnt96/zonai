import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return const AppConfig(
    appName: 'Concurrency Repro E2E',
    passwordSecret: 'e2e-password-pepper',
    jwtSecret: 'e2e-zonai-jwt-secret',
    baseUrl: 'http://localhost:8080',
  );
}
