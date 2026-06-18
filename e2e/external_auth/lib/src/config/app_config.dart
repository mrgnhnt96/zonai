import 'package:zonai_schema/zonai_schema.dart';

/// Supabase-shaped external IdP config (HS256 / shared secret).
AppConfig main() {
  return AppConfig(
    appName: 'External Auth E2E',
    passwordSecret: 'e2e-password-pepper',
    jwtSecret: 'e2e-zonai-jwt-secret',
    baseUrl: 'http://localhost:8080',
    externalIdps: const [
      SharedSecretIdpConfig(
        issuer: 'https://abcdefgh.supabase.co/auth/v1',
        audience: 'authenticated',
        authTable: 'users',
        secret: 'e2e-supabase-jwt-secret',
      ),
    ],
  );
}
