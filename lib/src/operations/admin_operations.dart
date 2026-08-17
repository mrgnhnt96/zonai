import '../schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class AdminOperations extends TableOperations<AdminTable, Admin> {
  AdminOperations() : super(admins);
}

AdminOperations main() => AdminOperations();
