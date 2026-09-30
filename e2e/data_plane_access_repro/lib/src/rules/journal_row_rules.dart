import 'package:zonai_data_plane_access_repro/src/schemas/journal.dart';
import 'package:zonai_schema/zonai_schema.dart';

JournalRowRules main() => JournalRowRules();

/// `notes`' owner-only rule, plus the scope that says the same thing as a
/// filter: a signed-in user reads only their own entries, and an admin reads
/// every entry.
class JournalRowRules extends RowRules<JournalTable, JournalEntry> {
  JournalRowRules() : super(journal);

  @override
  Future<Where?> viewScope(Jwt? jwt) async {
    if (jwt == null || jwt.admin.isAdmin) return null;
    return Eq('owner_id', jwt.userId.value);
  }

  @override
  Future<bool> canView(Jwt? jwt, JournalEntry row) async {
    if (jwt == null) return false;
    if (jwt.admin.isAdmin) return true;
    return jwt.userId.value == row.ownerId;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, JournalEntry row) async => true;

  @override
  Future<bool> canUpdate(
    Jwt? jwt,
    JournalEntry before,
    JournalEntry after,
  ) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, JournalEntry row) async => true;
}
