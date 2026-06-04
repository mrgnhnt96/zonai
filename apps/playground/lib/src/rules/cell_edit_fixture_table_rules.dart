import 'package:zonai_playground/src/schemas/cell_edit_fixtures.dart';
import 'package:zonai_schema/zonai_schema.dart';

CellEditFixtureTableRules main() => CellEditFixtureTableRules();

final class CellEditFixtureTableRules extends TableRules<CellEditFixtureTable, CellEditFixture> {
  CellEditFixtureTableRules() : super(cellEditFixtures);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  Future<bool> canUpdate(Jwt? jwt) async => true;

  Future<bool> canDelete(Jwt? jwt) async => true;

  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
