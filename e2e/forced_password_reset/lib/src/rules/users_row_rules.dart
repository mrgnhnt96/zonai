import 'package:zonai_forced_password_reset/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRowRules main() => UserRowRules();

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
}
