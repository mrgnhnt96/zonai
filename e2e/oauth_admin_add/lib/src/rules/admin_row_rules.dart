import 'package:zonai_oauth_admin_add_e2e/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminRowRules main() => AdminRowRules();

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  /// See `AdminTableRules.canList` -- opened for the same reason.
  @override
  Future<bool> canView(Jwt? jwt, Admin row) async => true;

  // `AdminTable` is `AsAdmin`, so `AuthRowRules.canSignUp` denies anonymous
  // sign-up by default -- see the doc comment there. This fixture seeds its
  // first admin over `POST /auth/sign-up`, so it opts back in explicitly.
  //
  // Not a pattern to copy: it makes every registrant an admin.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}
