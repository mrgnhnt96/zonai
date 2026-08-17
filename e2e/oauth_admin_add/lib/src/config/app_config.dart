import 'package:zonai_schema/zonai_schema.dart';

/// Baseline config compiled into `db_config.exe`. The e2e test overrides it
/// at runtime the same way `oauth_e2e_test.dart` does, so `baseUrl` here
/// only has to be *a* valid value.
AppConfig main() {
  return AppConfig(
    appName: 'OAuth Admin Add E2E',
    passwordSecret: 'e2e-password-pepper-UVIjjOrrfaPgnBBY9JSAeTV3jaXjz1ky',
    jwtSecret: 'e2e-zonai-jwt-secret-8q4KsoOw8bJzuesZfcwzkhjSsCLsll1',
    baseUrl: 'http://localhost:8080',
  );
}
