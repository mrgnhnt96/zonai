// Members of an auth table's operations file -- `addClaims` and the other
// AuthOperations overrides. `AuthOperations` is a mixin on TableOperations,
// not a base class of its own.
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations<UserTable, User> {
  UserOperations() : super(users);

  // <<body>>
}
