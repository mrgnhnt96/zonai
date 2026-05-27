import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRowRules main() => UserRowRules();

class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
}
