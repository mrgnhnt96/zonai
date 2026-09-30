import 'package:zonai_data_plane_access_repro/src/schemas/journal.dart';
import 'package:zonai_schema/zonai_schema.dart';

JournalTableRules main() => JournalTableRules();

/// Permissive at the table level, like `notes`.
final class JournalTableRules extends TableRules<JournalTable, JournalEntry> {
  JournalTableRules() : super(journal);

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
