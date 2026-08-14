import 'package:zonai_crud_matrix/src/schemas/widgets.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// One file per table: the generator loads exactly one [TableOperations] from
/// each operations file's `main()` (see `operation_generator.dart`), so a
/// second class in this file would never be registered.
final class WidgetOperations extends TableOperations<WidgetTable, Widget> {
  WidgetOperations() : super(widgets);
}

WidgetOperations main() => WidgetOperations();
