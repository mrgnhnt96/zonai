import 'package:zonai_admin_password_update_repro/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminRowRules main() => AdminRowRules();

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  // `AdminTable` is `AsAdmin`, so `AuthRowRules.canSignUp` denies anonymous
  // sign-up by default -- see the doc comment there. This fixture creates its
  // admin over `POST /auth/sign-up` (tool/ci/e2e/drive.dart), so it opts back
  // in explicitly. That the opt-in has to be written out is the point of the
  // default: without this line the driver's first request 403s, which is the
  // signal a real app would want.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}
