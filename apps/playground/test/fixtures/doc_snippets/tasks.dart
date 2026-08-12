// A stand-in for the `tasks` table the docs invent for their examples.
//
// The docs import it as `package:my_app/src/schemas/tasks.dart` -- `my_app`
// being the reader's own project, which by definition doesn't exist here.
// doc_snippets_test.dart rewrites that import to this file so the snippets
// around it can be analyzed. It only has to carry the shape the snippets
// reference (`Task`, `TaskTable`, `tasks`); if a snippet starts using a column
// this doesn't have, add it here rather than loosening the check.
import 'package:zonai_schema/zonai_schema.dart';

final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.isDone,
    required this.ownerId,
  });

  final TasksId id;
  final String title;
  final bool isDone;
  final String ownerId;
}

final class TasksId implements Id {
  const TasksId(this.value);

  factory TasksId.generate() => TasksId(Id.generate('ta'));

  @override
  final String value;

  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class TaskTable extends Table<Task> {
  TaskTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: TasksId.new,
        generate: TasksId.generate,
      ),
      title = $.text('title', (s) => s.title),
      isDone = $.boolean('is_done', (s) => s.isDone),
      ownerId = $.text('owner_id', (s) => s.ownerId);

  @override
  Task fromRow(RowReader read) => Task(
    id: read(id),
    title: read(title),
    isDone: read(isDone),
    ownerId: read(ownerId),
  );

  final IdColumn<TasksId> id;
  final TextColumn title;
  final BooleanColumn isDone;
  final TextColumn ownerId;
}

final tasks = table('tasks', TaskTable.new);
