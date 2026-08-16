import 'package:zonai_oauth_admin_add_e2e/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminRowRules main() => AdminRowRules();

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  /// See `AdminTableRules.canList` -- opened for the same reason.
  @override
  Future<bool> canView(Jwt? jwt, Admin row) async => true;
}
