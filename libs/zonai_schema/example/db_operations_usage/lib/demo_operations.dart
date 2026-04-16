import 'package:db_operations_usage/demo_schema.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class DemoOperations extends CollectionOperations<DemoWidget> {
  DemoOperations() : super(demoWidgets);
}
