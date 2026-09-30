import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:zonai_sync/zonai_sync.dart';

/// Maps one synced table between the app's drift schema and zonai's wire
/// format (the map the server sends and receives).
///
/// This is the only per-table code an app writes, and it is what
/// `zonai_sync_gen` generates from the server schema. Every method runs
/// inside the store's transaction when the engine needs atomicity.
abstract interface class DriftSyncTable {
  /// The zonai table name.
  String get name;

  /// The local row as a wire map, or null when it does not exist.
  Future<Map<String, Object?>?> read(String id);

  /// Inserts or replaces the local row from a wire map.
  Future<void> write(Map<String, Object?> wire);

  Future<void> delete(String id);

  /// Deletes every row (sign-out, or a different account signing in).
  Future<void> clear();
}

/// A [SyncLocalStore] backed by the app's own drift database.
///
/// Sync bookkeeping lives in four tables this store owns, prefixed
/// `_zonai_sync_` and created on [open]. Because they are in the SAME
/// database as the app's rows, a local edit and its outbox entry — or a
/// pulled page and its cursor — commit in one SQLite transaction.
///
/// Base revisions are kept here too, so app tables need no `rev` column.
final class DriftSyncStore implements SyncLocalStore {
  DriftSyncStore._(this._db, this._tables);

  /// Creates the bookkeeping tables if needed and returns the store.
  static Future<DriftSyncStore> open(
    GeneratedDatabase db,
    List<DriftSyncTable> tables,
  ) async {
    for (final ddl in _ddl) {
      await db.customStatement(ddl);
    }
    return DriftSyncStore._(db, {for (final t in tables) t.name: t});
  }

  static const _ddl = [
    'CREATE TABLE IF NOT EXISTS _zonai_sync_outbox ('
        'id INTEGER PRIMARY KEY, tbl TEXT NOT NULL, row_id TEXT NOT NULL, '
        'entry TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS _zonai_sync_outbox_row '
        'ON _zonai_sync_outbox (tbl, row_id)',
    'CREATE TABLE IF NOT EXISTS _zonai_sync_cursor ('
        'tbl TEXT PRIMARY KEY, cursor TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS _zonai_sync_base ('
        'tbl TEXT NOT NULL, row_id TEXT NOT NULL, rev INTEGER NOT NULL, '
        'PRIMARY KEY (tbl, row_id))',
    'CREATE TABLE IF NOT EXISTS _zonai_sync_meta ('
        'key TEXT PRIMARY KEY, value TEXT)',
  ];

  final GeneratedDatabase _db;
  final Map<String, DriftSyncTable> _tables;

  DriftSyncTable _table(String name) =>
      _tables[name] ??
      (throw ArgumentError('No DriftSyncTable registered for "$name"'));

  @override
  Future<T> transaction<T>(Future<T> Function() body) => _db.transaction(body);

  // ---- rows ----

  @override
  Future<LocalRow?> readRow(String table, String id) async {
    final data = await _table(table).read(id);
    if (data == null) return null;
    return LocalRow(data: data, baseRev: await _baseRev(table, id));
  }

  @override
  Future<void> writeRow(String table, Map<String, Object?> data) =>
      _table(table).write(data);

  @override
  Future<void> deleteRow(String table, String id) async {
    await _table(table).delete(id);
    await _db.customStatement(
      'DELETE FROM _zonai_sync_base WHERE tbl = ? AND row_id = ?',
      [table, id],
    );
  }

  @override
  Future<void> applyRemote(String table, RemoteRow row) async {
    if (row.isDeleted) {
      await deleteRow(table, row.id);
      return;
    }
    await _table(table).write(row.data);
    await setBaseRev(table, row.id, row.rev);
  }

  @override
  Future<void> setBaseRev(String table, String id, int rev) =>
      _db.customStatement(
        'INSERT INTO _zonai_sync_base (tbl, row_id, rev) VALUES (?, ?, ?) '
        'ON CONFLICT (tbl, row_id) DO UPDATE SET rev = excluded.rev',
        [table, id, rev],
      );

  Future<int?> _baseRev(String table, String id) async {
    final row = await _db
        .customSelect(
          'SELECT rev FROM _zonai_sync_base WHERE tbl = ? AND row_id = ?',
          variables: [Variable.withString(table), Variable.withString(id)],
        )
        .getSingleOrNull();
    return row?.read<int>('rev');
  }

  // ---- outbox ----

  /// Ids come from a monotonic counter, never MAX(id)+1: a reused id would
  /// let a stale push "settle" a newer entry that happened to get the same id.
  @override
  Future<int> nextOutboxId() async {
    final current = int.tryParse(await _meta('outbox_seq') ?? '') ?? 0;
    final next = current + 1;
    await _setMeta('outbox_seq', '$next');
    return next;
  }

  @override
  Future<OutboxEntry?> pendingFor(String table, String rowId) async {
    final row = await _db
        .customSelect(
          'SELECT entry FROM _zonai_sync_outbox WHERE tbl = ? AND row_id = ? '
          'ORDER BY id LIMIT 1',
          variables: [Variable.withString(table), Variable.withString(rowId)],
        )
        .getSingleOrNull();
    return row == null ? null : _decode(row.read<String>('entry'));
  }

  @override
  Future<void> putEntry(OutboxEntry entry) => _db.customStatement(
    'INSERT INTO _zonai_sync_outbox (id, tbl, row_id, entry) VALUES (?, ?, ?, ?) '
    'ON CONFLICT (id) DO UPDATE SET entry = excluded.entry',
    [entry.id, entry.table, entry.rowId, jsonEncode(entry.toJson())],
  );

  @override
  Future<void> removeEntry(int id) =>
      _db.customStatement('DELETE FROM _zonai_sync_outbox WHERE id = ?', [id]);

  @override
  Future<OutboxEntry?> entry(int id) async {
    final row = await _db
        .customSelect(
          'SELECT entry FROM _zonai_sync_outbox WHERE id = ?',
          variables: [Variable.withInt(id)],
        )
        .getSingleOrNull();
    return row == null ? null : _decode(row.read<String>('entry'));
  }

  @override
  Future<List<OutboxEntry>> entries() async {
    final rows = await _db
        .customSelect('SELECT entry FROM _zonai_sync_outbox ORDER BY id')
        .get();
    return [for (final r in rows) _decode(r.read<String>('entry'))];
  }

  static OutboxEntry _decode(String json) =>
      OutboxEntry.fromJson(jsonDecode(json) as Map<String, Object?>);

  // ---- cursors & account ----

  @override
  Future<SyncCursor?> cursor(String table) async {
    final row = await _db
        .customSelect(
          'SELECT cursor FROM _zonai_sync_cursor WHERE tbl = ?',
          variables: [Variable.withString(table)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return SyncCursor.fromJson(
      jsonDecode(row.read<String>('cursor')) as Map<String, Object?>,
    );
  }

  @override
  Future<void> setCursor(String table, SyncCursor cursor) =>
      _db.customStatement(
        'INSERT INTO _zonai_sync_cursor (tbl, cursor) VALUES (?, ?) '
        'ON CONFLICT (tbl) DO UPDATE SET cursor = excluded.cursor',
        [table, jsonEncode(cursor.toJson())],
      );

  @override
  Future<String?> account() => _meta('account');

  @override
  Future<void> setAccount(String? account) => _setMeta('account', account);

  @override
  Future<void> clearAll() async {
    for (final table in _tables.values) {
      await table.clear();
    }
    await _db.customStatement('DELETE FROM _zonai_sync_outbox');
    await _db.customStatement('DELETE FROM _zonai_sync_cursor');
    await _db.customStatement('DELETE FROM _zonai_sync_base');
  }

  Future<String?> _meta(String key) async {
    final row = await _db
        .customSelect(
          'SELECT value FROM _zonai_sync_meta WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    return row?.read<String?>('value');
  }

  Future<void> _setMeta(String key, String? value) => _db.customStatement(
    'INSERT INTO _zonai_sync_meta (key, value) VALUES (?, ?) '
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
    [key, value],
  );
}
