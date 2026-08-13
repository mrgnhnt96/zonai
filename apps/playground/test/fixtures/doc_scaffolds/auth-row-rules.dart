// Members of the row rules for an auth table -- `canSignUp`, `canSignIn` and
// `canPasswordReset`, which live here rather than on the table rules.
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);

  // <<body>>
}
