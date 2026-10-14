import 'package:zonai_admin_send_repro/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminTableRules main() => AdminTableRules();

final class AdminTableRules extends AuthTableRules<AdminTable, Admin> {
  AdminTableRules() : super(admins);

  /// See `AdminRowRules.canView`.
  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
