import 'package:zonai_forced_password_reset/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
}
