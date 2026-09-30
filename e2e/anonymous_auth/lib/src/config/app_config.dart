import 'package:zonai_schema/zonai_schema.dart';

// Plain words, not random-looking strings: long and varied enough for
// AppConfig's secret checks, and nothing a secret scanner should mistake for a
// credential. The e2e test replaces this config with one of its own anyway.
AppConfig main() {
  return AppConfig(
    appName: 'Anonymous Auth E2E',
    passwordSecret: 'anonymous-auth-fixture-password-pepper-for-tests',
    jwtSecret: 'anonymous-auth-fixture-token-signing-key-for-tests',
    baseUrl: 'http://localhost:8080',
  );
}
