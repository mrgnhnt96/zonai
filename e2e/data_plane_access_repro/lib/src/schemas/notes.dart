import 'package:zonai_data_plane_access_repro/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// A plain (non-auth) collection whose rules are permissive at the TABLE level
/// and restrictive at the ROW level — the shape `docs/rules.md` describes as
/// the normal one, and the shape the SSE stream leak depended on.
final class Note {
  Note({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.createdAt,
    this.updatedAt,
  });

  final NotesId id;
  final String title;
  final String ownerId;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class NoteTable extends Table<Note> {
  NoteTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: NotesId.new,
        generate: NotesId.generate,
      ),
      title = $.text('title', (s) => s.title),
      ownerId = $.text('owner_id', (s) => s.ownerId),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Note fromRow(RowReader read) {
    return Note(
      id: read(id),
      title: read(title),
      ownerId: read(ownerId),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<NotesId> id;
  final TextColumn title;
  final TextColumn ownerId;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final notes = table('notes', NoteTable.new);
