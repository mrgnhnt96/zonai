import 'package:zonai_external_auth_e2e/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
}
