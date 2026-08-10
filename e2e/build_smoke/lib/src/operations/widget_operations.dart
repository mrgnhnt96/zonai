import 'package:zonai_build_smoke/src/schemas/widgets.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Same reason as the rules: the operations worker is generated and compiled
/// separately, so it needs real content for the build to prove anything.
final class WidgetOperations extends TableOperations<WidgetTable, Widget> {
  WidgetOperations() : super(widgets);
}

WidgetOperations main() => WidgetOperations();
