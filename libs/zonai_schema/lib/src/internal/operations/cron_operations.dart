import 'package:zonai_schema/src/internal/tables/crons_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class CronOperations extends TableOperations<CronsTable, CronEntry> {
  CronOperations() : super(crons);
}

CronOperations main() => CronOperations();
