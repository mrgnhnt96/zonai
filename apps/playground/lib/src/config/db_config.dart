import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Banana',
    // Was `'password'` / `'jwt'`. A live pentest guessed the JWT one on the
    // first try and minted an admin token with it. `AppConfig.validate()` now
    // refuses both, so this would no longer start.
    passwordSecret: const String.fromEnvironment(
      'PASSWORD_SECRET',
      defaultValue: 'playground-password-pepper-Zt4Rq8mNvXcB3wKdHs6yLpJ2',
    ),
    jwtSecret: const String.fromEnvironment(
      'JWT_SECRET',
      defaultValue: 'playground-jwt-secret-Gf7YbQ5nTz9KwMr2VxHd4CsLp8Ja',
    ),
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
