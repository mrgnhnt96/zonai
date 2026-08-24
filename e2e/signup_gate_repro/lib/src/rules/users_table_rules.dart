import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signup_gate_repro/src/schemas/users.dart';

UserTableRules main() => UserTableRules();

/// Reading `users` is open here so the test can ask the question that matters:
/// after a declined sign-up, is the row there or not?
///
/// `canList` and `canView` both default to admin-only, and this fixture has no
/// admin — without these the assertion fails with "Access denied" whether the
/// gate worked or not, which is the one answer a test must never give.
final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;
}
