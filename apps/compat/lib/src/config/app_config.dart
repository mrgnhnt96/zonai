import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Compat Test',
    passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
    jwtSecret: const String.fromEnvironment('JWT_SECRET'),
    baseUrl: 'http://localhost:8080',
  );
}
