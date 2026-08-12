// A stand-in for the `tasks` table the docs invent for their examples.
//
// The docs import it as `package:my_app/src/schemas/tasks.dart` -- `my_app`
// being the reader's own project, which by definition doesn't exist here.
// doc_snippets_test.dart rewrites that import to this file so the snippets
// around it can be analyzed. It only has to carry the shape the snippets
// reference (`Task`, `TaskTable`, `tasks`); if a snippet starts using a column
// this doesn't have, add it here rather than loosening the check.
//
// The ID classes live in ids.dart, the same one place a real project keeps
// them, so a snippet importing both this and `package:my_app/src/ids.dart`
// sees one `TasksId` rather than two incompatible ones.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.isDone,
    required this.ownerId,
    required this.createdBy,
  });

  final TasksId id;
  final String title;
  final bool isDone;
  final String ownerId;

  /// The user who created the row, as an ID rather than a `String` -- the
  /// rules examples compare it against `Jwt.userId`, which is an `UnknownId`.
  /// Comparing an ID to a bare `String` is silently always false.
  final UnknownId createdBy;
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
      ownerId = $.text('owner_id', (s) => s.ownerId),
      createdBy = $.id<UnknownId, UnknownId>(
        'created_by',
        (s) => s.createdBy,
        fromString: UnknownId.new,
        generate: () => const UnknownId('__TASK_CREATOR__'),
        isPrimaryKey: false,
      );

  @override
  Task fromRow(RowReader read) => Task(
    id: read(id),
    title: read(title),
    isDone: read(isDone),
    ownerId: read(ownerId),
    createdBy: read(createdBy),
  );

  final IdColumn<TasksId> id;
  final TextColumn title;
  final BooleanColumn isDone;
  final TextColumn ownerId;
  final IdColumn<UnknownId> createdBy;
}

final tasks = table('tasks', TaskTable.new);
