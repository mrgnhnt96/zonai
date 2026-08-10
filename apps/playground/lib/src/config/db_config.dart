import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Banana',
    passwordSecret: 'password',
    jwtSecret: 'jwt',
    baseUrl: 'http://localhost:8080',
    email: EmailConfig(
      host: 'smtp.gmail.com',
      port: 587,
      username: 'you@example.com',
      password: const String.fromEnvironment('GMAIL_APP_PASSWORD'),
      from: EmailAddress(address: 'you@example.com', name: 'Link'),
    ),
    photos: PhotosConfig(
      // 100 bytes
      maxBytes: 100,
    ),
  );
}
