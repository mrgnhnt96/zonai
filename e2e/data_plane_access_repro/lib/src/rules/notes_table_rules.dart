import 'package:zonai_data_plane_access_repro/src/schemas/notes.dart';
import 'package:zonai_schema/zonai_schema.dart';

NoteTableRules main() => NoteTableRules();

/// Permissive at the table level, exactly as `docs/rules.md` describes the
/// coarse gate: anyone may *ask* to list notes. What they are allowed to see
/// is decided per row, in [NoteRowRules].
final class NoteTableRules extends TableRules<NoteTable, Note> {
  NoteTableRules() : super(notes);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;
}
