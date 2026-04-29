import 'package:raindrop/raindrop.dart' show DatabaseResult;
import 'package:zonai/src/db_mutator/objected_row.dart';

class OperationResult {
  OperationResult(this._result);

  final DatabaseResult? _result;

  int get rowsAffected => _result?.rowsAffected ?? 0;

  List<ObjectedRow> get rows => [
    for (final row in _result?.rows ?? [])
      ObjectedRow(columns: _result?.columns ?? [], values: row),
  ];
}
