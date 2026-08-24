import 'package:zonai_forced_password_reset/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

AdminTableRules main() => AdminTableRules();

final class AdminTableRules extends AuthTableRules<AdminTable, Admin> {
  AdminTableRules() : super(admins);
}
