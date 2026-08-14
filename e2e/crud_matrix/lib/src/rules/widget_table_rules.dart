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
}
