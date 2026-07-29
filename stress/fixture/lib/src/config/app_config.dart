import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return const AppConfig(
    appName: 'Zonai Stress Fixture',
    passwordSecret: 'stress-password-pepper',
    jwtSecret: 'stress-zonai-jwt-secret',
    baseUrl: 'http://localhost:8099',
  );
}
