import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Data Plane Access E2E',
    // >=32 chars: the integrated F-10 validator (min 32) rejects the short
    // placeholders this fixture originally shipped with. Lengthened during the
    // sec-leaf integration so the data-plane e2e can boot.
    passwordSecret: 'e2e-password-pepper-Kp7Wm2Qx9Zt4Rb8Hn6Ls',
    jwtSecret: 'e2e-zonai-jwt-secret-Vc5Yd3Gf8Nq1Jw6Ma2Xr',
    baseUrl: 'http://localhost:8080',
  );
}
