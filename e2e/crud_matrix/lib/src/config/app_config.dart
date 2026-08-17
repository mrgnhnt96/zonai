import 'package:zonai_schema/zonai_schema.dart';

/// The host refuses to serve without a compiled config worker, so the fixture
/// needs one. These are fixture values for a server that only ever answers a
/// CI runner on loopback; they are not credentials.
AppConfig main() {
  return const AppConfig(
    appName: 'Zonai CRUD Matrix',
    passwordSecret:
        'crud-matrix-password-pepper-KW3PvuKi9E7Kk4ayngZT2DmjSrtbCKn',
    jwtSecret: 'crud-matrix-jwt-secret-W1ICKTqJEEH3bdfxL4EY5Ahnc7HnaM',
    baseUrl: 'http://localhost:8080',
  );
}
