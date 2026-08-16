import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Insecure Test Mode E2E',
    passwordSecret: 'insecure-test-mode-e2e-pw-Zt4Rq8mNvXcB3wKdHs6yLpJ2',
    jwtSecret: 'insecure-test-mode-e2e-jwt-Gf7YbQ5nTz9KwMr2VxHd4CsLp8Ja',
    baseUrl: 'http://localhost:8080',
  );
}
