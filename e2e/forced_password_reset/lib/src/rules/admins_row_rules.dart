import 'package:zonai_forced_password_reset/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminRowRules main() => AdminRowRules();

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  // `AdminTable` is `AsAdmin`, so `AuthRowRules.canSignUp` denies anonymous
  // sign-up by default. This fixture seeds its admin through
  // `ZonaiDb.authenticate`, so it opts back in explicitly. Not a pattern to
  // copy into an app: it makes every registrant an admin.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}
