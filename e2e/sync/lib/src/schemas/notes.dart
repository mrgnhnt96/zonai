import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_sync_e2e/src/ids.dart';

/// A table shaped for zonai_sync on today's zonai:
///
/// * `updated_at` is NON-nullable, so zonai stamps it on insert as well as on
///   update. A nullable one is NULL until the first update, and a cursor pull
///   (`updated_at > cursor`) never sees rows that are created and never
///   edited.
/// * `rev` is the revision the client conditions its updates on.
/// * `deleted_at` is the tombstone; rows are never hard-deleted.
final class Note {
  Note({
    required this.id,
    required this.ownerId,
    required this.rev,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.body,
    this.deletedAt,
  });

  final NotesId id;
  final String ownerId;
  final String? title;
  final String? body;
  final int rev;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

final class NoteTable extends Table<Note> {
  NoteTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: NotesId.new,
        generate: NotesId.generate,
      ),
      ownerId = $.text('owner_id', (s) => s.ownerId),
      title = $.text('title', (s) => s.title),
      body = $.text('body', (s) => s.body),
      rev = $.integer('rev', (s) => s.rev),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt),
      deletedAt = $.dateTime('deleted_at', (s) => s.deletedAt);

  @override
  Note fromRow(RowReader read) => Note(
    id: read(id),
    ownerId: read(ownerId),
    title: read(title),
    body: read(body),
    rev: read(rev),
    createdAt: read(createdAt),
    updatedAt: read(updatedAt),
    deletedAt: read(deletedAt),
  );

  final IdColumn<NotesId> id;
  final TextColumn ownerId;
  final ColumnType<String?> title;
  final ColumnType<String?> body;
  final IntColumn rev;
  final DateTimeColumn createdAt;
  final DateTimeColumn updatedAt;
  final ColumnType<DateTime?> deletedAt;
}

final notes = table('notes', NoteTable.new);
