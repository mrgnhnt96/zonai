import 'dart:async';

import 'package:zonai_sync/src/cursor.dart';
import 'package:zonai_sync/src/local.dart';
import 'package:zonai_sync/src/outbox.dart';
import 'package:zonai_sync/src/remote.dart';

/// A [SyncLocalStore] in memory: the reference implementation of the port's
/// contract, and the store used by tests. Transactions snapshot and restore
/// everything, so a failure inside one leaves no partial state behind.
base class MemorySyncStore implements SyncLocalStore {
  var _rows = <String, Map<String, LocalRow>>{};
  var _outbox = <int, OutboxEntry>{};
  var _cursors = <String, SyncCursor>{};
  String? _account;
  var _nextId = 1;

  /// Read-only view of a table, for assertions.
  Map<String, LocalRow> rows(String table) =>
      Map.unmodifiable(_rows[table] ?? {});

  /// Transactions are SERIALIZED (like SQLite's single writer) and nesting is
  /// tracked per zone: a transaction opened inside another joins it, while an
  /// unrelated one that starts concurrently waits its turn. A shared depth
  /// counter would make the concurrent one run "inside" the first and roll
  /// back with it.
  @override
  Future<T> transaction<T>(Future<T> Function() body) async {
    if (Zone.current[_zoneKey] == this) return body();

    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    await previous;
    final rows = {for (final e in _rows.entries) e.key: Map.of(e.value)};
    final outbox = Map.of(_outbox);
    final cursors = Map.of(_cursors);
    final account = _account;
    final nextId = _nextId;
    try {
      return await runZoned(body, zoneValues: {_zoneKey: this});
    } on Object {
      _rows = rows;
      _outbox = outbox;
      _cursors = cursors;
      _account = account;
      _nextId = nextId;
      rethrow;
    } finally {
      done.complete();
    }
  }

  static final _zoneKey = Object();
  Future<void> _lock = Future.value();

  @override
  Future<LocalRow?> readRow(String table, String id) async => _rows[table]?[id];

  @override
  Future<void> writeRow(String table, Map<String, Object?> data) async {
    final id = data[SyncFields.id]! as String;
    final existing = _rows[table]?[id];
    (_rows[table] ??= {})[id] = LocalRow(
      data: Map.unmodifiable(data),
      baseRev: existing?.baseRev,
    );
  }

  @override
  Future<void> deleteRow(String table, String id) async =>
      _rows[table]?.remove(id);

  @override
  Future<List<String>> rowIds(String table) async =>
      (_rows[table]?.keys ?? const <String>[]).toList();

  @override
  Future<void> applyRemote(String table, RemoteRow row) async {
    if (row.isDeleted) {
      _rows[table]?.remove(row.id);
      return;
    }
    (_rows[table] ??= {})[row.id] = LocalRow(
      data: Map.unmodifiable(row.data),
      baseRev: row.rev,
    );
  }

  @override
  Future<void> setBaseRev(String table, String id, int rev) async {
    final existing = _rows[table]?[id];
    if (existing == null) return;
    _rows[table]![id] = LocalRow(data: existing.data, baseRev: rev);
  }

  @override
  Future<int> nextOutboxId() async => _nextId++;

  @override
  Future<OutboxEntry?> pendingFor(String table, String rowId) async {
    for (final e in _outbox.values) {
      if (e.table == table && e.rowId == rowId) return e;
    }
    return null;
  }

  @override
  Future<void> putEntry(OutboxEntry entry) async => _outbox[entry.id] = entry;

  @override
  Future<void> removeEntry(int id) async => _outbox.remove(id);

  @override
  Future<OutboxEntry?> entry(int id) async => _outbox[id];

  @override
  Future<List<OutboxEntry>> entries() async =>
      _outbox.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  @override
  Future<SyncCursor?> cursor(String table) async => _cursors[table];

  @override
  Future<void> setCursor(String table, SyncCursor cursor) async =>
      _cursors[table] = cursor;

  @override
  Future<String?> account() async => _account;

  @override
  Future<void> setAccount(String? account) async => _account = account;

  @override
  Future<void> clearAll() async {
    _rows = {};
    _outbox = {};
    _cursors = {};
  }
}
