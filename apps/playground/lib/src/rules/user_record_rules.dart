import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart' hide User;

UserRecordRules main() => UserRecordRules();

class UserRecordRules extends RecordRules<User> {
  UserRecordRules() : super(users);
}
