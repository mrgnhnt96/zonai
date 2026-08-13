// Members of a table rules class, over the `tasks` table the docs invent.
import 'package:my_app/src/schemas/tasks.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class TaskTableRules extends TableRules<TaskTable, Task> {
  TaskTableRules() : super(tasks);

  // <<body>>
}
