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

  /// Every row, as a filter. Row rules that check each row need a scope for
  /// `/db/count` to answer at all (#45); this one admits everything, so the
  /// count still covers the whole table while per-row checks keep running.
  @override
  Future<Where?> viewScope(Jwt? jwt) async => const NotNull('id');

  @override
  Future<bool> canUpdate(Jwt? jwt, Widget before, Widget after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Widget row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Widget row) async => true;

  @override
  Map<String, CustomRowOperationRule<Widget>> get customOperations => {
    'restock': (jwt, before, after) async => true,
  };
}
