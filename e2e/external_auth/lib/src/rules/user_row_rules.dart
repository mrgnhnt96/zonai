import 'package:zonai_external_auth_e2e/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRowRules main() => UserRowRules();

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
}
