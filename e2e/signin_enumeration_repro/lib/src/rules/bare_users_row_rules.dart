import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signin_enumeration_repro/src/schemas/bare_users.dart';

BareUserRowRules main() => BareUserRowRules();

final class BareUserRowRules extends AuthRowRules<BareUserTable, BareUser> {
  BareUserRowRules() : super(bareUsers);

  /// See `BareUserTableRules.canList`.
  @override
  Future<bool> canView(Jwt? jwt, BareUser row) async => true;
}
