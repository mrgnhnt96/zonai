import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signin_enumeration_repro/src/schemas/users.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  /// Opened so the test can observe whether a failed sign-in left a row
  /// behind. Auth never consults [canList], so this does not weaken the
  /// behaviour under test.
  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
