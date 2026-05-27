import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRecordRules main() => UserRecordRules();

class UserRecordRules extends AuthRecordRules<UserTable, User> {
  UserRecordRules() : super(users);
}
