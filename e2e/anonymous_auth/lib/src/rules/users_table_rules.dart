import 'package:zonai_anonymous_auth_fixture/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserTableRules main() => UserTableRules();

/// Users may update their own row, so the test can show the framework's
/// default row rule is what keeps an anonymous account's address unwritable.
final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;
}
