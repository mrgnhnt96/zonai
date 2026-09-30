import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_sync_e2e/src/schemas/notes.dart';

NoteRowRules main() => NoteRowRules();

/// Owner-only, checked on BOTH sides of an update so a row cannot be handed
/// to someone else. Hard deletes are refused: sync deletes are tombstones.
final class NoteRowRules extends RowRules<NoteTable, Note> {
  NoteRowRules() : super(notes);

  bool _owns(Jwt? jwt, Note row) =>
      jwt != null && jwt.userId.value == row.ownerId;

  @override
  Future<bool> canView(Jwt? jwt, Note row) async => _owns(jwt, row);

  @override
  Future<bool> canCreate(Jwt? jwt, Note row) async => _owns(jwt, row);

  @override
  Future<bool> canUpdate(Jwt? jwt, Note before, Note after) async =>
      _owns(jwt, before) && _owns(jwt, after);

  @override
  Future<bool> canDelete(Jwt? jwt, Note row) async => false;
}
