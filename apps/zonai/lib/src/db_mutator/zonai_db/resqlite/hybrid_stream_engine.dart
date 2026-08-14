// Ported from raindrop_sqlite's hybrid_stream_engine.dart -- see
// resqlite_delegate.dart in this directory for why.

import 'dart:async';
import 'dart:collection';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'sql_read_dependencies.dart';
import 'package:resqlite/resqlite.dart' as rs;

/// Reactive stream engine that reads via main-isolate sqlite3 and invalidates
/// from resqlite writer dirty-table notifications.
final class HybridStreamEngine {
  HybridStreamEngine(this._read);

  final Future<DatabaseResult> Function(String sql, List<Object?> params) _read;

  final Map<int, _HybridStreamEntry> _entries = {};
  final Set<_HybridStreamEntry> _unknownDepsEntries = {};
  final Map<String, Set<_HybridStreamEntry>> _tableIndex = {};
  final _requeryQueue = LinkedHashSet<_HybridStreamEntry>();
  var _closed = false;

  Stream<DatabaseResult> stream(String sql, [List<Object?> params = const []]) {
    if (_closed) {
      throw StateError('HybridStreamEngine is closed.');
    }

    final key = _streamKey(sql, params);
    final existing = _entries[key];
    if (existing != null) {
      return _subscribe(existing);
    }
    return _createStream(key, sql, params);
  }

  void onDependencyChanges(rs.TableDependencies changes) {
    if (_closed || _entries.isEmpty) return;

    if (changes case rs.FixedTableDependencies(
      :final tables,
    ) when tables.isEmpty) {
      return;
    }

    final dirtyEntries = <_HybridStreamEntry>{};

    switch (changes) {
      case rs.UnknownTableDependencies():
        dirtyEntries.addAll(_unknownDepsEntries);
        for (final entries in _tableIndex.values) {
          dirtyEntries.addAll(entries);
        }
      case rs.FixedTableDependencies(:final tables):
        dirtyEntries.addAll(_unknownDepsEntries);
        for (final dep in tables) {
          if (_tableIndex[dep.table] case Set<_HybridStreamEntry> entries) {
            switch (dep) {
              case rs.TableColumnDependency(:final columns):
                for (final entry in entries) {
                  switch (entry.dependencies[dep.table]) {
                    case rs.TableColumnDependency(
                      columns: final watchedColumns,
                    ):
                      if (watchedColumns.intersection(columns).isNotEmpty) {
                        dirtyEntries.add(entry);
                      }
                    case rs.TableDependency _:
                      dirtyEntries.add(entry);
                    case null:
                      break;
                  }
                }
              case rs.TableDependency():
                dirtyEntries.addAll(entries);
            }
          }
        }
    }

    for (final entry in dirtyEntries) {
      entry.dirty = true;
      if (!entry.inFlight) {
        _requeryQueue.add(entry);
      }
    }

    _flushQueue();
  }

  void close() {
    _closed = true;
    for (final entry in _entries.values) {
      for (final sub in entry.subscribers) {
        if (!sub.isClosed) sub.close();
      }
      entry.subscribers.clear();
    }
    _entries.clear();
    _tableIndex.clear();
    _unknownDepsEntries.clear();
    _requeryQueue.clear();
  }

  void _flushQueue() {
    if (_requeryQueue.isEmpty) return;
    for (final entry in _requeryQueue.toList()) {
      _requeryQueue.remove(entry);
      unawaited(_requery(entry));
    }
  }

  Stream<DatabaseResult> _createStream(
    int key,
    String sql,
    List<Object?> params,
  ) {
    final entry = _entries[key] = _HybridStreamEntry(
      key: key,
      sql: sql,
      params: params,
    );
    entry.inFlight = true;
    _unknownDepsEntries.add(entry);

    final subscriberStream = _subscribe(entry);

    unawaited(
      Future.sync(() async {
        try {
          final initial = await _read(sql, params);
          if (entry.subscribers.isEmpty) return;

          entry.lastResult = initial;
          _registerDependencies(entry, readDependenciesForStreamSql(sql));
          // A brand-new subscriber has seen nothing yet, so the connect-time
          // snapshot must always reach it -- even if a write's dependency
          // change landed while this read was in flight. Skipping the emit
          // here (as if `initial` were already-known state) silently drops
          // the only copy of it a caller will ever get: a later requery that
          // happens to read the same values back will treat them as
          // unchanged and emit nothing at all.
          entry.emit(initial);

          if (entry.dirty) {
            _requeryQueue.add(entry);
            _flushQueue();
          }
        } catch (e, stackTrace) {
          entry.emitError(e, stackTrace);
          _remove(entry);
        } finally {
          entry.inFlight = false;
        }
      }),
    );

    return subscriberStream;
  }

  void _registerDependencies(
    _HybridStreamEntry entry,
    rs.TableDependencies dependencies,
  ) {
    if (dependencies case rs.FixedTableDependencies(:final tables)) {
      _unknownDepsEntries.remove(entry);
      for (final dependency in tables) {
        (_tableIndex[dependency.table] ??= {}).add(entry);
      }
      entry.dependencies = {
        for (final dependency in tables) dependency.table: dependency,
      };
    }
  }

  Future<void> _requery(_HybridStreamEntry entry) async {
    try {
      entry.inFlight = true;
      entry.dirty = false;

      final next = await _read(entry.sql, entry.params);
      if (entry.dirty) {
        _requeryQueue.add(entry);
        return;
      }

      final last = entry.lastResult;
      if (last != null && _resultsEqual(last, next)) {
        return;
      }

      entry.lastResult = next;
      entry.emit(next);
    } catch (e, st) {
      entry.emitError(e, st);
    } finally {
      entry.inFlight = false;
      _flushQueue();
    }
  }

  Stream<DatabaseResult> _subscribe(_HybridStreamEntry entry) {
    final controller = StreamController<DatabaseResult>();
    entry.subscribers.add(controller);

    controller.onCancel = () {
      entry.subscribers.remove(controller);
      if (!controller.isClosed) controller.close();
      if (entry.subscribers.isEmpty) {
        _remove(entry);
      }
    };

    final cached = entry.lastResult;
    if (cached != null) {
      controller.add(cached);
    }

    return controller.stream;
  }

  void _remove(_HybridStreamEntry entry) {
    _entries.remove(entry.key);
    _requeryQueue.remove(entry);
    for (final table in entry.dependencies.keys) {
      _tableIndex[table]?.remove(entry);
    }
    _unknownDepsEntries.remove(entry);
    for (final sub in entry.subscribers) {
      if (!sub.isClosed) sub.close();
    }
    entry.subscribers.clear();
  }
}

final class _HybridStreamEntry {
  _HybridStreamEntry({
    required this.key,
    required this.sql,
    required this.params,
    // ignore: unused_element_parameter
    this.dependencies = const {},
  });

  final int key;
  final String sql;
  final List<Object?> params;
  Map<String, rs.TableDependency> dependencies;
  final List<StreamController<DatabaseResult>> subscribers = [];
  DatabaseResult? lastResult;
  var dirty = false;
  var inFlight = false;

  void emit(DatabaseResult result) {
    for (final sub in subscribers) {
      if (!sub.isClosed) sub.add(result);
    }
  }

  void emitError(Object e, StackTrace? st) {
    for (final sub in subscribers) {
      if (!sub.isClosed) sub.addError(e, st);
    }
  }
}

int _streamKey(String sql, List<Object?> params) =>
    Object.hash(sql, Object.hashAll(params));

bool _resultsEqual(DatabaseResult a, DatabaseResult b) {
  if (a.columns.length != b.columns.length || a.rows.length != b.rows.length) {
    return false;
  }
  for (var r = 0; r < a.rows.length; r++) {
    final rowA = a.rows[r];
    final rowB = b.rows[r];
    if (rowA.length != rowB.length) return false;
    for (var c = 0; c < rowA.length; c++) {
      if (rowA[c] != rowB[c]) return false;
    }
  }
  return true;
}
