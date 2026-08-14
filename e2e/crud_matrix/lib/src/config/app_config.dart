import 'package:zonai_schema/zonai_schema.dart';

/// The host refuses to serve without a compiled config worker, so the fixture
/// needs one. These are fixture values for a server that only ever answers a
/// CI runner on loopback; they are not credentials.
AppConfig main() {
  return const AppConfig(
    appName: 'Zonai CRUD Matrix',
    passwordSecret: 'crud-matrix-password-pepper',
    jwtSecret: 'crud-matrix-jwt-secret',
    baseUrl: 'http://localhost:8080',
  );
}
