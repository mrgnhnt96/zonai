import 'package:zonai_oauth_e2e/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRowRules main() => UserRowRules();

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);

  /// See `UserTableRules.canList` -- opened for the same reason.
  @override
  Future<bool> canView(Jwt? jwt, User row) async => true;
}
