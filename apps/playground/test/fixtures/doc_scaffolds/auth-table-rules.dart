// Members of the table rules for an auth table -- `canAuthenticate` and the
// table-level checks. `AuthTableRules` is a base class you extend, not a
// mixin, and an `AuthTable` is not a `Table`, so `TableRules<UserTable, User>`
// will not accept one.
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  // <<body>>
}
