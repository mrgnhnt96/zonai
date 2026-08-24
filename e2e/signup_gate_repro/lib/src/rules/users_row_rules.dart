import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signup_gate_repro/src/schemas/users.dart';

UserRowRules main() => UserRowRules();

/// Row-level reads are open for the same reason the table-level ones are: the
/// test's "no row was created" assertion has to be able to see rows that DO
/// exist, or it proves nothing about the one that should not.
final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);

  @override
  Future<bool> canView(Jwt? jwt, User row) async => true;
}
