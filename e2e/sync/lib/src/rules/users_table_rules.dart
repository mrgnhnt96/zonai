import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_sync_e2e/src/schemas/users.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
}
