import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signin_enumeration_repro/src/schemas/bare_users.dart';

BareUserTableRules main() => BareUserTableRules();

final class BareUserTableRules extends AuthTableRules<BareUserTable, BareUser> {
  BareUserTableRules() : super(bareUsers);

  /// See `UserTableRules.canList` — opened only so the test can observe the
  /// rows a failed sign-in may have created.
  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
