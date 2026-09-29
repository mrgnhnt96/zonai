import 'package:zonai_anonymous_auth_fixture/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Something an account owns, so a test can show an upgraded account still
/// owns what it wrote while anonymous.
final class Note {
  Note({required this.id, required this.ownerId, required this.body});

  final NotesId id;
  final String ownerId;
  final String body;
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
      body = $.text('body', (s) => s.body);

  @override
  Note fromRow(RowReader read) {
    return Note(id: read(id), ownerId: read(ownerId), body: read(body));
  }

  final IdColumn<NotesId> id;
  final TextColumn ownerId;
  final TextColumn body;
}

final notes = table('notes', NoteTable.new);
