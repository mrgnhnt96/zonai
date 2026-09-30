import 'package:zonai_data_plane_access_repro/src/schemas/boards.dart';
import 'package:zonai_schema/zonai_schema.dart';

BoardTableRules main() => BoardTableRules();

/// Permissive at the table level, like `journal`.
final class BoardTableRules extends TableRules<BoardTable, Board> {
  BoardTableRules() : super(boards);

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
