import 'package:zonai_data_plane_access_repro/src/schemas/boards.dart';
import 'package:zonai_schema/zonai_schema.dart';

BoardRowRules main() => BoardRowRules();

/// Every row viewable and updatable, but reads scoped to the caller's own.
class BoardRowRules extends RowRules<BoardTable, Board> {
  BoardRowRules() : super(boards);

  @override
  Future<Where?> viewScope(Jwt? jwt) async {
    if (jwt == null || jwt.admin.isAdmin) return null;
    return Eq('owner_id', jwt.userId.value);
  }

  @override
  Future<bool> canView(Jwt? jwt, Board row) async => jwt != null;

  @override
  Future<bool> canCreate(Jwt? jwt, Board row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Board before, Board after) async =>
      jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt, Board row) async => true;
}
