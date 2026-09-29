import 'package:zonai_anonymous_auth_fixture/src/schemas/notes.dart';
import 'package:zonai_schema/zonai_schema.dart';

NoteTableRules main() => NoteTableRules();

final class NoteTableRules extends TableRules<NoteTable, Note> {
  NoteTableRules() : super(notes);

  @override
  Future<bool> canView(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canList(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;
}
