sealed class CrudException implements Exception {
  const CrudException({required this.table});

  final String table;
}

final class RecordNotFoundException extends CrudException {
  const RecordNotFoundException({required super.table, this.id});

  final String? id;

  @override
  String toString() {
    if (id != null) return 'Record not found: $id (table: $table)';
    return 'Record not found (table: $table)';
  }
}

final class RecordDeletedWhileStreamingException extends CrudException {
  const RecordDeletedWhileStreamingException({required super.table, this.id});

  final String? id;

  @override
  String toString() {
    if (id != null) return 'Record was deleted while streaming: $id (table: $table)';
    return 'Record not found or was deleted (table: $table)';
  }
}

final class RecordCreateFailedException extends CrudException {
  const RecordCreateFailedException({required super.table, this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to create record in $table: $cause';
    return 'Failed to create record in $table';
  }
}

final class RecordReadFailedException extends CrudException {
  const RecordReadFailedException({required super.table, this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to read record from $table: $cause';
    return 'Failed to read record from $table';
  }
}

final class RecordUpdateFailedException extends CrudException {
  const RecordUpdateFailedException({required super.table, this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to update record(s) in $table: $cause';
    return 'Failed to update record(s) in $table';
  }
}

final class RecordDeleteFailedException extends CrudException {
  const RecordDeleteFailedException({required super.table, this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to delete record(s) from $table: $cause';
    return 'Failed to delete record(s) from $table';
  }
}

final class RecordListFailedException extends CrudException {
  const RecordListFailedException({required super.table, this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to list records from $table: $cause';
    return 'Failed to list records from $table';
  }
}

final class RecordCountFailedException extends CrudException {
  const RecordCountFailedException({required super.table, this.cause});

  final Object? cause;

  @override
  String toString() {
    if (cause != null) return 'Failed to count records in $table: $cause';
    return 'Failed to count records in $table';
  }
}

final class PasswordUpdateForbiddenException extends CrudException {
  const PasswordUpdateForbiddenException({required super.table});

  @override
  String toString() =>
      'Only admins with edit access can update the password column on table "$table"';
}

final class InvalidPasswordUpdateException extends CrudException {
  const InvalidPasswordUpdateException({required super.table});

  @override
  String toString() =>
      'Password column on table "$table" can only be updated with a plain string value';
}

final class ForeignKeyConstraintException extends CrudException {
  const ForeignKeyConstraintException({required super.table});

  @override
  String toString() => 'That reference does not match an existing row.';
}

final class UniqueConstraintException extends CrudException {
  const UniqueConstraintException({required super.table});

  @override
  String toString() => 'A record with that value already exists.';
}

final class InvalidColumnValueException extends CrudException {
  const InvalidColumnValueException({required super.table, this.cause});

  final Object? cause;

  @override
  String toString() =>
      'An ID field has an invalid format. Use the full text ID (for example test-1234567890_co).';
}
