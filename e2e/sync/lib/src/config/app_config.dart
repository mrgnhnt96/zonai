import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'zonai_sync E2E',
    passwordSecret: 'e2e-sync-password-pepper-Qm4Tz8Wc2Lk6Xv9R',
    jwtSecret: 'e2e-sync-zonai-jwt-secret-Hb7Nd3Pf5Ys1Gq8J',
    baseUrl: 'http://localhost:8080',
  );
}
