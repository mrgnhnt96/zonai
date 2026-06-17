import 'package:zonai_schema/src/internal/tables/abusers_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class AbuserOperations
    extends TableOperations<AbusersTable, AbuserEntry> {
  AbuserOperations() : super(abusers);
}

AbuserOperations main() => AbuserOperations();
