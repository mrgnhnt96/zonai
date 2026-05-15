import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(passwordSecret: 'password', jwtSecret: 'jwt');
}
