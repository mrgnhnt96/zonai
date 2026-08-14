import 'package:zonai_crud_matrix/src/schemas/gates.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class GateOperations extends TableOperations<GateTable, Gate> {
  GateOperations() : super(gates);
}

GateOperations main() => GateOperations();
