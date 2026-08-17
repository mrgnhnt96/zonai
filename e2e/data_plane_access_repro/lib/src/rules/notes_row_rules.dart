import 'package:zonai_data_plane_access_repro/src/schemas/notes.dart';
import 'package:zonai_schema/zonai_schema.dart';

NoteRowRules main() => NoteRowRules();

/// The real gate: a note is visible only to the signed-in user whose id it
/// carries.
///
/// An anonymous caller passes [NoteTableRules.canList] and fails every row,
/// which is the arrangement the SSE leak turned inside out — the table rule let
/// the subscription open, and nothing re-checked the rows that arrived after.
class NoteRowRules extends RowRules<NoteTable, Note> {
  NoteRowRules() : super(notes);

  @override
  Future<bool> canView(Jwt? jwt, Note row) async {
    if (jwt == null) return false;
    return jwt.userId.value == row.ownerId;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, Note row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Note before, Note after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Note row) async => true;
}
