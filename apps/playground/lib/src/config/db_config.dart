import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Banana',
    passwordSecret: 'password',
    jwtSecret: 'jwt',
    baseUrl: 'http://localhost:8091',
    email: EmailConfig(
      host: 'smtp.gmail.com',
      port: 587,
      username: 'mrgnhnt96@gmail.com',
      password: const String.fromEnvironment('GMAIL_APP_PASSWORD'),
      from: EmailAddress(address: 'mrgnhnt96@gmail.com', name: 'Link'),
    ),
  );
}
