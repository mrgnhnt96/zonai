import 'package:zonai_build_smoke/src/schemas/widgets.dart';
import 'package:zonai_schema/zonai_schema.dart';

WidgetRowRules main() => WidgetRowRules();

/// Present so `zonai build` has a real rule to generate and compile into the
/// rules worker -- an empty project would bundle an empty worker and prove
/// less than nothing about the build.
class WidgetRowRules extends RowRules<WidgetTable, Widget> {
  WidgetRowRules() : super(widgets);

  @override
  Future<bool> canView(Jwt? jwt, Widget row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Widget before, Widget after) async => false;

  @override
  Future<bool> canDelete(Jwt? jwt, Widget row) async => false;

  @override
  Future<bool> canCreate(Jwt? jwt, Widget row) async => true;
}
