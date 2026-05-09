import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart' hide User;

UserRecordRules main() => UserRecordRules();

class UserRecordRules extends AuthRecordRules<User> {
  UserRecordRules() : super(users);
}
