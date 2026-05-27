part of 'table_operations.dart';

class TableTranslator {
  TableTranslator(this.dbTable, this.dialect);

  final _DbTable dbTable;
  final BaseSqlDialect dialect;

  (String, List<Object?>) translate(PerformOperationRequest request) {
    return dbTable._translate(dialect, request);
  }
}
