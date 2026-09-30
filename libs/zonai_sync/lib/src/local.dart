import 'package:zonai_sync/src/cursor.dart';
import 'package:zonai_sync/src/outbox.dart';
import 'package:zonai_sync/src/remote.dart';

/// A synced row as the device holds it.
final class LocalRow {
  const LocalRow({required this.data, required this.baseRev});

  /// Wire-format map of the row's current local state.
  final Map<String, Object?> data;

  /// The server revision the local copy descends from; null if the row has
  /// never been on the server.
  final int? baseRev;
}

/// The device side of sync. The local database is the source of truth; this
/// port lets the engine read and write it without knowing its schema.
///
/// Every method is called inside [transaction] where atomicity matters: a
/// local write and its outbox entry, or a pulled page and its cursor, commit
/// together or not at all.
abstract interface class SyncLocalStore {
  /// Runs [body] atomically. Await everything [body] starts: work left
  /// running unawaited inside a transaction outlives it, and still counts as
  /// "inside" it (it inherits the zone), so it would skip the serialisation
  /// a later transaction relies on.
  Future<T> transaction<T>(Future<T> Function() body);

  // ---- synced rows ----
  Future<LocalRow?> readRow(String table, String id);

  /// Writes the local state of a row (a local edit). Does not touch baseRev.
  Future<void> writeRow(String table, Map<String, Object?> data);

  /// Removes a row locally.
  Future<void> deleteRow(String table, String id);

  /// Ids of every row held locally in [table].
  Future<List<String>> rowIds(String table);

  /// Stores what the server has: data plus its revision as the new base.
  /// A tombstone ([RemoteRow.isDeleted]) removes the row locally.
  Future<void> applyRemote(String table, RemoteRow row);

  /// Records that the local row now descends from server revision [rev].
  Future<void> setBaseRev(String table, String id, int rev);

  // ---- outbox ----
  Future<int> nextOutboxId();
  Future<OutboxEntry?> pendingFor(String table, String rowId);
  Future<void> putEntry(OutboxEntry entry);
  Future<void> removeEntry(int id);
  Future<OutboxEntry?> entry(int id);

  /// Every entry (pending and dead), ascending by id.
  Future<List<OutboxEntry>> entries();

  // ---- cursors & account ----
  Future<SyncCursor?> cursor(String table);
  Future<void> setCursor(String table, SyncCursor cursor);

  /// The account whose data this store holds, or null when empty.
  Future<String?> account();
  Future<void> setAccount(String? account);

  /// Deletes every synced row, the outbox and all cursors, atomically.
  Future<void> clearAll();
}
