import 'package:meta/meta.dart';
import 'package:zonai_sync/src/cursor.dart';

/// Reserved wire fields every synced row carries.
abstract final class SyncFields {
  static const id = 'id';
  static const rev = 'rev';
  static const updatedAt = 'updated_at';
  static const deletedAt = 'deleted_at';
}

/// A row as the server returned it: its wire map plus the sync metadata the
/// server owns. Clients never compare their own clock against [updatedAt].
@immutable
final class RemoteRow {
  const RemoteRow(this.data);

  final Map<String, Object?> data;

  String get id => data[SyncFields.id]! as String;
  int get rev => (data[SyncFields.rev] as int?) ?? 0;
  int get updatedAt => data[SyncFields.updatedAt]! as int;
  bool get isDeleted => data[SyncFields.deletedAt] != null;

  SyncCursor get cursor => SyncCursor(updatedAt: updatedAt, id: id);

  @override
  String toString() =>
      'RemoteRow($id, rev $rev${isDeleted ? ', deleted' : ''})';
}

/// One page of a pull, in ascending cursor order.
@immutable
final class PullPage {
  const PullPage({required this.rows, required this.hasMore});

  final List<RemoteRow> rows;
  final bool hasMore;
}

/// Restricts a pull to the rows the signed-in user owns.
///
/// Mandatory for owned tables: zonai refuses a WHOLE list with 403 when any
/// row fails `canView`, so an unscoped pull breaks the moment another user's
/// row sorts after the cursor (gravity_brew bug class #3).
@immutable
final class SyncScope {
  const SyncScope(this.column, this.value);

  final String column;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is SyncScope && other.column == column && other.value == value;

  @override
  int get hashCode => Object.hash(column, value);
}

/// How the engine should react to a failure. The remote adapter maps its
/// transport's errors onto these; the engine never parses messages.
enum FailureKind {
  /// No connection, DNS failure, timeout: retry without spending an attempt.
  offline,

  /// 401 — the session is gone. Pause everything until re-authenticated.
  unauthorized,

  /// 403 — this user may not do this. Retrying cannot help: dead-letter.
  forbidden,

  /// 400/422 — the server rejects the payload. Dead-letter.
  invalid,

  /// 409 on create — a row with this id already exists.
  exists,

  /// 409/412 on a conditional update — the row moved past our base revision.
  revisionConflict,

  /// 404 — no such row (deleted, or never existed).
  notFound,

  /// 429 — back off until [SyncRemoteException.retryAfter].
  rateLimited,

  /// 5xx or anything unclassified: retry with backoff, spending an attempt.
  server,
}

final class SyncRemoteException implements Exception {
  const SyncRemoteException(
    this.kind, {
    this.message = '',
    this.current,
    this.retryAfter,
  });

  final FailureKind kind;
  final String message;

  /// For [FailureKind.exists] / [FailureKind.revisionConflict]: the server's
  /// current row, when the transport returns it.
  final RemoteRow? current;
  final Duration? retryAfter;

  @override
  String toString() => 'SyncRemoteException(${kind.name}: $message)';
}

/// The server side of sync. `ZonaiSyncRemote` implements it for zonai; tests
/// use a fake. Every method throws [SyncRemoteException] on failure.
abstract interface class SyncRemote {
  /// Creates [row] (which carries its client-chosen id). Throws
  /// [FailureKind.exists] when that id is taken.
  Future<RemoteRow> create(String table, Map<String, Object?> row);

  /// Applies [changes] to row [id] only if its revision is still [ifRev].
  /// Throws [FailureKind.revisionConflict] (with `current` when available) if
  /// it moved, [FailureKind.notFound] if it does not exist.
  Future<RemoteRow> update(
    String table,
    String id,
    Map<String, Object?> changes, {
    required int ifRev,
  });

  /// The row as the server has it now, or null when it does not exist.
  Future<RemoteRow?> read(String table, String id);

  /// Rows changed strictly after [after] (from the beginning when null),
  /// in ascending cursor order, INCLUDING tombstones, restricted to [scope].
  Future<PullPage> pull(
    String table, {
    required SyncScope? scope,
    required SyncCursor? after,
    required int limit,
  });
}
