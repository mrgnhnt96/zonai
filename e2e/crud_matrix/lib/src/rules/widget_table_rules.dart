import 'package:zonai_crud_matrix/src/schemas/widgets.dart';
import 'package:zonai_schema/zonai_schema.dart';

WidgetTableRules main() => WidgetTableRules();

final class WidgetTableRules extends TableRules<WidgetTable, Widget> {
  WidgetTableRules() : super(widgets);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  /// `restock` is open to anyone, same as the rest of this fixture's table --
  /// the base [customOperations] map defaults to `{}` (every named operation
  /// denied), so a route that only had its [WidgetOperations.custom]
  /// implemented and not this entry would 403 rather than run.
  @override
  Map<String, CustomTableOperationRule> get customOperations => {
    'restock': (jwt) async => true,
  };
}
