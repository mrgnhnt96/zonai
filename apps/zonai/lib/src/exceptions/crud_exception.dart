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
    if (id != null)
      return 'Record was deleted while streaming: $id (table: $table)';
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
      'Only admins with edit access can set the password column on table "$table"';
}

final class InvalidPasswordUpdateException extends CrudException {
  const InvalidPasswordUpdateException({required super.table});

  @override
  String toString() =>
      'Password column on table "$table" can only be set with a plain string value';
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

/// Thrown when too many mutating requests are already queued for the single
/// SQLite writer. Mapped to HTTP 503 so clients can retry instead of waiting
/// on a multi-second busy-timeout spin.
/// Thrown when a write failed because the volume holding the database has no
/// space left.
///
/// This exists because of what the raw failure looks like: SQLite reports
/// "database or disk is full" or a bare "disk I/O error", which reaches an
/// operator as a generic write failure on whichever request happened to be
/// unlucky. Nothing in it says the disk is the problem, and nothing says what
/// to do — a production deployment sat at 100% for thirteen days with its
/// health check green, because a full volume does not stop a process, it only
/// stops it writing.
///
/// The message names the remedy, because at zero bytes free the database
/// cannot fix itself: reclaiming space needs a write, and that is the write
/// being refused.
final class DiskFullException implements Exception {
  const DiskFullException({this.path, this.cause});

  /// The database's location, when known — an operator needs to know which
  /// volume to grow, not just that one is full.
  final String? path;
  final Object? cause;

  @override
  String toString() {
    final where = path == null ? '' : ' holding $path';
    return 'No space left on the volume$where. Writes are failing and the '
        'database cannot reclaim space on its own, because reclaiming it '
        'requires a write. Extend the volume, then let retention run and '
        'vacuum to return the freed pages to the operating system.';
  }
}

/// What the `retry-after` header says on a backpressure 503, in whole seconds.
///
/// A floor, not a prediction. The write queue drains in tens of milliseconds
/// and the server does not know when a slot will free, so it does not pretend
/// to: 1s is the smallest value HTTP can express, and the point of sending it
/// is that a well-behaved client stops spinning, not that it returns at the
/// exact instant a slot opens. What it buys is measured on the client side,
/// not the server's: since `674a59e1` refusing is already cheap here, so the
/// thing that keeps a saturated queue saturated is a caller with no backoff
/// re-sending into it immediately -- stress/README.md records ~98% of writes
/// refused at concurrency 100, and notes that making rejection cheaper let the
/// generator land *more* attempts in the same window rather than fewer. Any
/// wait at all breaks that loop, and a whole second is the shortest one
/// `Retry-After` can say.
///
/// One constant for both directions of backpressure, so the read-side twin
/// cannot drift from the write side. Never 0: `Retry-After: 0` is an
/// instruction to retry into the same full queue.
const kBackpressureRetryAfterSeconds = 1;

final class WriteBackpressureException implements Exception {
  const WriteBackpressureException();

  @override
  String toString() =>
      'Server is busy writing; retry shortly (write queue saturated).';
}

/// Thrown when too many concurrent read requests (read/list/count) are
/// already in flight. Unlike [WriteBackpressureException], reads aren't
/// serialized -- this caps how many can run *concurrently* rather than how
/// many are waiting for a turn -- but without it a burst of concurrent reads
/// has no ceiling and just queues behind the rules-worker's single
/// stdin/stdout pipe with ever-growing latency instead of failing fast.
/// Mapped to HTTP 503 so clients can retry instead of waiting indefinitely.
final class ReadBackpressureException implements Exception {
  const ReadBackpressureException();

  @override
  String toString() =>
      'Server is busy reading; retry shortly (read concurrency saturated).';
}
