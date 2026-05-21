import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Banana',
    passwordSecret: 'password',
    jwtSecret: 'jwt',
    email: EmailConfig(
      host: 'smtp.gmail.com',
      port: 587,
      username: 'mrgnhnt96@gmail.com',
      password: 'bpek vnrv cilx ccev',
      from: EmailAddress(address: 'mrgnhnt96@gmail.com', name: 'Link'),
    ),
  );
}
