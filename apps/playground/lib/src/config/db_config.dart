import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'Banana',
    passwordSecret: 'password',
    jwtSecret: 'jwt',
    email: EmailConfig(
      host: 'smtp.gmail.com',
      port: 587,
      username: 'link@hyrule.com',
      password: 'heroOfHyrule00T1!',
      from: EmailAddress(address: 'link@hyrule.com', name: 'Link'),
    ),
  );
}
