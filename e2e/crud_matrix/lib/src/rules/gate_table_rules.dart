import 'package:zonai_crud_matrix/src/schemas/gates.dart';
import 'package:zonai_schema/zonai_schema.dart';

GateTableRules main() => GateTableRules();

final class GateTableRules extends TableRules<GateTable, Gate> {
  GateTableRules() : super(gates);

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
