sealed class SchemaException implements Exception {
  const SchemaException();
}

final class ColumnNotExpandableException extends SchemaException {
  const ColumnNotExpandableException({
    required this.table,
    required this.columnName,
  });

  final String table;
  final String columnName;

  @override
  String toString() => 'Column "$columnName" on "$table" cannot be expanded';
}

final class ColumnNotFoundException extends SchemaException {
  const ColumnNotFoundException({
    required this.table,
    required this.columnName,
  });

  final String table;
  final String columnName;

  @override
  String toString() => 'Column "$columnName" not found on table "$table"';
}

final class ExpandedRecordReadFailedException extends SchemaException {
  const ExpandedRecordReadFailedException({this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to read expanded record: $cause';
    return 'Failed to read expanded record';
  }
}

final class DatabaseNotOpenException extends SchemaException {
  const DatabaseNotOpenException();

  @override
  String toString() => 'Database is not open';
}

final class TableNotRegisteredException extends SchemaException {
  const TableNotRegisteredException({required this.table});

  final String table;

  @override
  String toString() => 'Table "$table" is not registered';
}
