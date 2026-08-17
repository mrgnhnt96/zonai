import 'package:zonai_schema/zonai_schema.dart';

/// Baseline config compiled into `db_config.exe`. Tests override it at
/// runtime via `configResolverProvider.overrideWith(() =>
/// ConfigResolver.fixed(appConfig))` (see `ZonaiDb._run`'s doc on why the
/// override is the only thing that actually takes effect), so `baseUrl`
/// here only has to be *a* valid value, not the one a given test asserts
/// `redirect_uri`/`redirect_to` against.
AppConfig main() {
  return AppConfig(
    appName: 'OAuth E2E',
    passwordSecret: 'e2e-password-pepper-UVIjjOrrfaPgnBBY9JSAeTV3jaXjz1ky',
    jwtSecret: 'e2e-zonai-jwt-secret-8q4KsoOw8bJzuesZfcwzkhjSsCLsll1',
    baseUrl: 'http://localhost:8080',
  );
}
