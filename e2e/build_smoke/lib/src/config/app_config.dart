import 'package:zonai_schema/zonai_schema.dart';

/// A project without a config cannot serve at all -- the host refuses to
/// start when `.zonai/executables/db_config.exe` is missing -- so the fixture
/// needs one for the bundle to be genuinely deployable.
///
/// These secrets are fixture values for a server that only ever answers
/// /health on a CI runner; they are not credentials.
AppConfig main() {
  return const AppConfig(
    appName: 'Zonai Build Smoke',
    passwordSecret:
        'build-smoke-password-pepper-hAxdYZJQbJiPoUORYnjP6jBkWpLCSrOi',
    jwtSecret: 'build-smoke-jwt-secret-jkVId7MNsmPtRPvInzI4B71BGG0lOZmu',
    baseUrl: 'http://localhost:8080',
  );
}
