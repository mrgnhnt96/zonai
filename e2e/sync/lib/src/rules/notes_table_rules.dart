import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_sync_e2e/src/schemas/notes.dart';

NoteTableRules main() => NoteTableRules();

/// Signed-in users may ask for anything; the row rules decide. Allowing
/// canUpdate/canDelete HERE matters: zonai checks the table rule before it
/// looks the row up, so an admin-only default would refuse every member's
/// write with 403 (gravity_brew bug class #2).
final class NoteTableRules extends TableRules<NoteTable, Note> {
  NoteTableRules() : super(notes);

  @override
  Future<bool> canView(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canList(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt) async => false;
}
