import 'package:zonai/src/internal/tables/logs_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class LogOperations extends TableOperations<LogsTable, LogEntry> {
  LogOperations() : super(logs);
}

LogOperations main() => LogOperations();
