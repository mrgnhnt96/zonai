import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: 'change-me-password-secret',
    jwtSecret: 'change-me-jwt-secret',
    baseUrl: 'http://localhost:8080',
    email: EmailConfig(
      host: 'smtp.example.com',
      port: 587,
      username: 'user@example.com',
      password: 'change-me',
      from: EmailAddress(address: 'noreply@example.com', name: 'My App'),
    ),
  );
}
