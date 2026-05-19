import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Banana',
    passwordSecret: 'password',
    jwtSecret: 'jwt',
  );
}
