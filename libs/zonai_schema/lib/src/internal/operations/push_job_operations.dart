import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class PushJobOperations
    extends TableOperations<PushJobsTable, PushJobEntry> {
  PushJobOperations() : super(pushJobs);
}

PushJobOperations main() => PushJobOperations();
