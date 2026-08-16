import 'package:zonai_data_plane_access_repro/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminRowRules main() => AdminRowRules();

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  // `AdminTable` is `AsAdmin`, so the integrated `AuthRowRules.canSignUp` (F-3)
  // denies anonymous admin sign-up by default. This e2e fixture bootstraps its
  // admin over `POST /auth/sign-up`, so it deliberately opts back in — the same
  // override the sibling repro fixtures carry.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}
