import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return const AppConfig(
    appName: 'Concurrency Repro E2E',
    passwordSecret: 'e2e-password-pepper-UVIjjOrrfaPgnBBY9JSAeTV3jaXjz1ky',
    jwtSecret: 'e2e-zonai-jwt-secret-8q4KsoOw8bJzuesZfcwzkhjSsCLsll1',
    baseUrl: 'http://localhost:8080',
  );
}
