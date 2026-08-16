import 'package:zonai_oauth_admin_add_e2e/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminTableRules main() => AdminTableRules();

final class AdminTableRules extends AuthTableRules<AdminTable, Admin> {
  AdminTableRules() : super(admins);

  /// Opened so the e2e suite can assert directly on what landed in the
  /// database, the same reason `oauth_e2e_test.dart`'s `UserTableRules`
  /// opens it.
  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
