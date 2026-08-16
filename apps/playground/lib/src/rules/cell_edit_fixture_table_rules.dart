import 'package:zonai_playground/src/schemas/cell_edit_fixtures.dart';
import 'package:zonai_schema/zonai_schema.dart';

CellEditFixtureTableRules main() => CellEditFixtureTableRules();

/// OPEN ON PURPOSE, unlike its neighbours.
///
/// `cell_edit_fixtures` exists only to give the dashboard's cell editor one
/// row of every column type to write against; it holds no real data and is
/// never served anywhere but a local playground. Authorization here would
/// test the fixture rather than the editor.
///
/// The tables next to this one (`posts`, `companies`, `items`, `authors`)
/// are the ones to copy from -- they used to be `=> true` as well, which is
/// the reason this file now has to say why it still is.
final class CellEditFixtureTableRules
    extends TableRules<CellEditFixtureTable, CellEditFixture> {
  CellEditFixtureTableRules() : super(cellEditFixtures);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
