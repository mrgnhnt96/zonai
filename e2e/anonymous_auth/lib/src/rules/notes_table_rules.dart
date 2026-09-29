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

  /// Editing is for verified accounts: the rule the docs show, and the one
  /// the verdict cache must not answer from an anonymous session's past.
  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null && !jwt.isAnonymous;
}
