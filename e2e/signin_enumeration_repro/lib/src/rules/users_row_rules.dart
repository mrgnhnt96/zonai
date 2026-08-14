import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signin_enumeration_repro/src/schemas/users.dart';

UserRowRules main() => UserRowRules();

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);

  /// See [UserTableRules.canList] — opened only so the test can observe the
  /// rows a failed sign-in may have created.
  @override
  Future<bool> canView(Jwt? jwt, User row) async => true;
}
