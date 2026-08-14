import 'package:zonai_crud_matrix/src/schemas/widgets.dart';
import 'package:zonai_schema/zonai_schema.dart';

WidgetRowRules main() => WidgetRowRules();

/// Everything permitted. The point of this fixture is the CRUD/operator
/// matrix, and a rule that says no is indistinguishable from a broken query
/// once it reaches HTTP -- both are "the row is not there".
///
/// Deliberately does NOT call `get.*`: a rule that reads the table it gates
/// re-enters rule evaluation. The worker-side read lives on `gates` instead.
class WidgetRowRules extends RowRules<WidgetTable, Widget> {
  WidgetRowRules() : super(widgets);

  @override
  Future<bool> canView(Jwt? jwt, Widget row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Widget before, Widget after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Widget row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Widget row) async => true;
}
