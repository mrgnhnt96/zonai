import 'package:zonai_oauth_e2e/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  /// Opened so the e2e suite can assert directly on what landed in the
  /// database (row counts after linking/dedup), the same reason
  /// `signin_enumeration_repro`'s table rules open it.
  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
