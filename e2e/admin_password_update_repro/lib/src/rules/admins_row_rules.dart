import 'package:zonai_admin_password_update_repro/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminRowRules main() => AdminRowRules();

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);
}
