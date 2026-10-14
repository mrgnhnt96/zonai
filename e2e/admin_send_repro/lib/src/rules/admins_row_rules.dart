import 'package:zonai_admin_send_repro/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminRowRules main() => AdminRowRules();

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  // `AsAdmin` denies anonymous sign-up by default. The test bootstraps its
  // one real admin through the password sign-up, so it opts back in, as the
  // sibling repro fixtures do.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;

  /// Opened only so the test can check that a send created no row.
  @override
  Future<bool> canView(Jwt? jwt, Admin row) async => true;
}
