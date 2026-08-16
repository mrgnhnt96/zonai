sealed class SchemaException implements Exception {
  const SchemaException();
}

/// Thrown when a `push` names something that cannot be a recipient set.
///
/// A [SchemaException] rather than an exception of its own, because every
/// case is a statement about the *shape* of the named collection: it does not
/// exist, the named column does not exist, the named column is not a
/// `deviceToken` column, or the table has no primary key to page by. Being
/// one also means it survives `ZonaiDb._run`, which wraps anything it does
/// not recognise in an opaque `StateError` — and an app author who pointed
/// `push` at the wrong column deserves to be told which column.
final class PushTargetException extends SchemaException {
  const PushTargetException(this.message);

  final String message;

  @override
  String toString() => message;
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

/// Thrown when a `RowRulesRequest`/`BatchRowRulesRequest` wire payload for an
/// update operation has no `updates` field at all, rather than treating that
/// as "no updates" (`after == before`).
///
/// An up-to-date sender always writes `updates` (even `[]`) — see
/// `RowRulesRequest.toJson`/`BatchRowRulesRequest.toJson`. Its total absence
/// means the payload predates issue #23's before/after `canUpdate` change,
/// so `canUpdate` can't be trusted to see the real post-write row. Refusing
/// loudly here is safer than silently authorizing against a stale `after`.
final class StaleRowRulesRequestException extends SchemaException {
  const StaleRowRulesRequestException({
    required this.table,
    required this.operation,
  });

  final String table;
  final String operation;

  @override
  String toString() =>
      'Row rules request for "$table" ($operation) has no "updates" field. '
      'This looks like a pre-issue-#23 sender (predates before/after '
      'canUpdate) rather than a request with genuinely no updates — refusing '
      'rather than silently treating after as identical to before.';
}

/// Thrown when a custom operation's payload carries `updates` but no `where`.
///
/// A custom op with no `where` skips row rules entirely and authorizes on
/// the table rule alone (see `_customOperationBuild`). Table rules are
/// documented as the permissive, coarse gate — real protection lives in row
/// rules (`docs/rules.md`) — so that combination would let a permissive
/// table rule authorize an unbounded write across every row in the table.
/// Refusing this shape outright makes it unrepresentable rather than merely
/// discouraged.
final class CustomOperationRequiresWhereException extends SchemaException {
  const CustomOperationRequiresWhereException({
    required this.table,
    required this.operation,
  });

  final String table;
  final String operation;

  @override
  String toString() =>
      'Custom operation "$operation" on "$table" has "updates" but no '
      '"where" — this would authorize a table-wide write on the table rule '
      'alone, bypassing row rules. Provide "where" whenever "updates" is '
      'non-empty.';
}
