sealed class PermissionException implements Exception {
  const PermissionException({required this.table, required this.operation});

  final String table;
  final String operation;
}

final class TableAccessDeniedException extends PermissionException {
  const TableAccessDeniedException({
    required super.table,
    required super.operation,
  });

  @override
  String toString() => 'Access denied: action "$operation" on table "$table"';
}

final class RowAccessDeniedException extends PermissionException {
  const RowAccessDeniedException({
    required super.table,
    required super.operation,
  });

  @override
  String toString() =>
      'Access denied: action "$operation" on a row in table "$table"';
}
