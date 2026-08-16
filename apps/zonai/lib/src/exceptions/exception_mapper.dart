import 'package:zonai_schema/src/exceptions/schema_exception.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';

import 'auth_exception.dart';
import 'crud_exception.dart';
import 'permission_exception.dart';
import 'photo_exception.dart';

/// Maps raw database, worker, and SQL errors to typed [CrudException]s and
/// [SchemaException]s.
Object mapDatabaseError(
  Object error, {
  required String table,
  Object Function(Object? cause)? orElse,
}) {
  if (error is AuthException ||
      error is CrudException ||
      error is PhotoException ||
      error is SchemaException ||
      error is PermissionException ||
      error is DiskFullException) {
    return error;
  }

  final message = _errorMessage(error);

  if (tryParseSchemaException(message) case final parsed?) {
    return parsed;
  }

  final lower = message.toLowerCase();

  // Checked before the constraint cases: a full volume can surface as a
  // write failure on any statement, so it would otherwise be reported as
  // whatever operation happened to be running when the disk ran out. The
  // three spellings are SQLITE_FULL, the errno underneath it, and
  // SQLITE_IOERR_WRITE, which is what a full disk usually looks like once
  // the WAL cannot be extended.
  if (lower.contains('database or disk is full') ||
      lower.contains('no space left on device') ||
      lower.contains('disk i/o error')) {
    return DiskFullException(cause: error);
  }

  if (lower.contains('foreign key constraint failed') ||
      lower.contains('foreign key')) {
    return ForeignKeyConstraintException(table: table);
  }

  if (lower.contains('unique constraint failed') ||
      lower.contains('unique constraint')) {
    return UniqueConstraintException(table: table);
  }

  if (error is FormatException || message.contains('Invalid radix-10 number')) {
    return InvalidColumnValueException(table: table, cause: error);
  }

  if (message.contains('Unknown column on table')) {
    final columnName =
        _parseQuoted(message, prefix: 'Unknown column on table "') ??
        _parseQuoted(message, prefix: 'column: ');
    if (columnName != null) {
      return ColumnNotFoundException(table: table, columnName: columnName);
    }
  }

  if (orElse != null) {
    return orElse(error);
  }

  return error is Exception ? error : StateError(message);
}

Object mapWorkerError(
  MessageHandlerFailedException error, {
  required String? table,
}) {
  final cause = error.cause ?? error.message;
  return mapDatabaseError(cause, table: table ?? 'unknown');
}

SchemaException? tryParseSchemaException(String message) {
  final tableNotRegistered = RegExp(r'Table "([^"]+)" is not registered');
  if (tableNotRegistered.firstMatch(message) case final match?) {
    return TableNotRegisteredException(table: match.group(1)!);
  }

  final columnNotFound = RegExp(
    r'Column "([^"]+)" not found on table "([^"]+)"',
  );
  if (columnNotFound.firstMatch(message) case final match?) {
    return ColumnNotFoundException(
      table: match.group(2)!,
      columnName: match.group(1)!,
    );
  }

  final columnNotExpandable = RegExp(
    r'Column "([^"]+)" on "([^"]+)" cannot be expanded',
  );
  if (columnNotExpandable.firstMatch(message) case final match?) {
    return ColumnNotExpandableException(
      table: match.group(2)!,
      columnName: match.group(1)!,
    );
  }

  // Thrown inside the operations worker (`TableOperations._validateWhere`),
  // so like the cases above it arrives here as message text. Without this it
  // degraded to a bare StateError and the caller got a 500 -- an "internal
  // error" for a request the server deliberately refused.
  final secretColumnFilter = RegExp(
    r'Column "([^"]+)" on "([^"]+)" is a secret column',
  );
  if (secretColumnFilter.firstMatch(message) case final match?) {
    return SecretColumnFilterException(
      table: match.group(2)!,
      columnName: match.group(1)!,
    );
  }

  final customOperationCollision = RegExp(
    r'Custom operation "([^"]+)" on "([^"]+)" is named after a classic',
  );
  if (customOperationCollision.firstMatch(message) case final match?) {
    return CustomOperationNameCollisionException(
      table: match.group(2)!,
      operation: match.group(1)!,
    );
  }

  final customOperationUnimplemented = RegExp(
    r'Custom operation "([^"]+)" is not implemented for table "([^"]+)"',
  );
  if (customOperationUnimplemented.firstMatch(message) case final match?) {
    return CustomOperationNotImplementedException(
      table: match.group(2)!,
      operation: match.group(1)!,
    );
  }

  if (message == 'Database is not open') {
    return const DatabaseNotOpenException();
  }

  return null;
}

String? operationRequestTable(OperationRequest request) {
  return switch (request) {
    GetColumnNameRequest(:final table) => table,
    GetColumnReferenceRequest(:final table) => table,
    PerformOperationRequest(:final table) => table,
    ViewAuthOperationRequest(:final table) => table,
    CreateAuthOperationRequest(:final table) => table,
    GetJwtConfigOperationRequest(:final table) => table,
    GetTableAdminStatusRequest(:final table) => table,
    SanitizeOperationRequest(:final table) => table,
    GetMagicLinkConfigOperationRequest(:final table) => table,
    GetResetPasswordConfigOperationRequest(:final table) => table,
    GetVerifyEmailConfigOperationRequest(:final table) => table,
    GetAllTableSchemaShapesRequest() ||
    GetAdminTablesOperationRequest() => null,
  };
}

String _errorMessage(Object error) => switch (error) {
  StateError(:final message) => message,
  FormatException(:final message) => message,
  ArgumentError(:final message) => message?.toString() ?? error.toString(),
  _ => error.toString(),
};

String? _parseQuoted(String message, {required String prefix}) {
  final start = message.indexOf(prefix);
  if (start < 0) return null;
  final quoteStart = start + prefix.length;
  if (quoteStart >= message.length || message[quoteStart] != '"') {
    return null;
  }
  final valueStart = quoteStart + 1;
  final valueEnd = message.indexOf('"', valueStart);
  if (valueEnd < 0) return null;
  return message.substring(valueStart, valueEnd);
}
