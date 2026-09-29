import 'package:zonai_anonymous_auth_fixture/src/schemas/notes.dart';
import 'package:zonai_schema/zonai_schema.dart';

NoteRowRules main() => NoteRowRules();

final class NoteRowRules extends RowRules<NoteTable, Note> {
  NoteRowRules() : super(notes);

  @override
  Future<bool> canView(Jwt? jwt, Note row) async =>
      jwt != null && row.ownerId == jwt.userId.value;

  @override
  Future<bool> canCreate(Jwt? jwt, Note row) async =>
      jwt != null && row.ownerId == jwt.userId.value;
}
