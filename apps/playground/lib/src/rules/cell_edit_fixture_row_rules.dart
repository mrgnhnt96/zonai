import 'package:zonai_playground/src/schemas/cell_edit_fixtures.dart';
import 'package:zonai_schema/zonai_schema.dart';

CellEditFixtureRowRules main() => CellEditFixtureRowRules();

/// Open on purpose -- see the note in `cell_edit_fixture_table_rules.dart`.
class CellEditFixtureRowRules
    extends RowRules<CellEditFixtureTable, CellEditFixture> {
  CellEditFixtureRowRules() : super(cellEditFixtures);

  @override
  Future<bool> canView(Jwt? jwt, CellEditFixture row) async => true;

  @override
  Future<bool> canUpdate(
    Jwt? jwt,
    CellEditFixture before,
    CellEditFixture after,
  ) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, CellEditFixture row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, CellEditFixture row) async => true;
}
