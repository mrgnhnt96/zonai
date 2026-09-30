import 'dart:async';

import 'package:zonai_sync/src/local.dart';
import 'package:zonai_sync/src/outbox.dart';
import 'package:zonai_sync/src/remote.dart';
import 'package:zonai_sync/src/retry.dart';
import 'package:zonai_sync/src/status.dart';
import 'package:zonai_sync/src/table.dart';

/// Keeps a device's local database and a zonai server in step.
///
/// The local store is the source of truth: the app reads and writes it
/// through [write] / [delete] (which also queue the change) and never waits on
/// the network. [sync] pushes queued changes, then pulls what changed on the
/// server. Guarantees, each of which a hand-built sync engine got wrong:
///
/// * a local write and its outbox entry commit together;
/// * creates are sent as creates (never update-then-create, which zonai
///   answers with 403 before it ever looks for the row);
/// * every pull of an owned table carries its owner scope;
/// * conflicts are decided by server revision, never by comparing clocks;
/// * data belongs to one account: a different account clears it first;
/// * a trigger during a running sync schedules another run — never dropped;
/// * nothing fails silently: permanent failures become dead letters.
final class SyncEngine {
  SyncEngine({
    required this._remote,
    required this._local,
    required List<SyncTable> tables,
    required this._account,
    this._retry = const RetryPolicy(),
    DateTime Function()? now,
    this.pageSize = 200,
    this.minInterval = const Duration(seconds: 20),
    this.syncOnWrite = true,
  }) : _tables = orderTables(tables),
       _now = now ?? DateTime.now;

  final SyncRemote _remote;
  final SyncLocalStore _local;
  final List<SyncTable> _tables;
  final String? Function() _account;
  final RetryPolicy _retry;
  final DateTime Function() _now;
  final int pageSize;

  /// Whether [write] and [delete] start a sync immediately (the default: a
  /// change reaches the server as soon as there is a connection).
  final bool syncOnWrite;

  /// Non-forced [requestSync] calls closer together than this are coalesced.
  final Duration minInterval;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = SyncStatus.initial;
  Future<void>? _running;
  Completer<void>? _rerun;
  DateTime? _lastRunStarted;
  Timer? _periodic;

  Stream<SyncStatus> get status => _statusController.stream;
  SyncStatus get currentStatus => _status;

  SyncTable _table(String name) => _tables.firstWhere(
    (t) => t.name == name,
    orElse: () => throw ArgumentError('Unknown sync table "$name"'),
  );

  int _order(String table) => _tables.indexWhere((t) => t.name == table);

  // ---------------------------------------------------------------- writes

  /// Writes [row] locally and queues it for the server, atomically.
  ///
  /// [row] must carry its id. [changed] names the fields this edit touched;
  /// when omitted it is computed against the stored row.
  Future<void> write(
    String table,
    Map<String, Object?> row, {
    Set<String>? changed,
  }) async {
    final t = _table(table);
    if (!t.pushes) throw StateError('$table is pull-only');
    final id = row[SyncFields.id];
    if (id is! String || id.isEmpty) {
      throw ArgumentError('A synced row needs a String id');
    }
    await _adoptAccount(_requireAccount());
    await _local.transaction(() async {
      final existing = await _local.readRow(table, id);
      final touched = {
        ...changed ??
            (existing == null
                ? row.keys
                : row.keys.where((k) => existing.data[k] != row[k])),
      }..removeAll(_serverOwned);
      await _local.writeRow(table, row);
      final pending = await _local.pendingFor(table, id);
      await _queue(
        Outbox.coalesce(
          pending: pending,
          newId: await _local.nextOutboxId(),
          table: table,
          rowId: id,
          op: OutboxOp.upsert,
          payload: _clientFields(row),
          changedFields: touched,
          baseRev: existing?.baseRev,
        ),
      );
    });
    await _publishCounts();
    if (syncOnWrite) unawaited(requestSync(force: true));
  }

  /// Deletes row [id] locally and queues a tombstone for the server.
  Future<void> delete(String table, String id) async {
    final t = _table(table);
    if (!t.pushes) throw StateError('$table is pull-only');
    await _adoptAccount(_requireAccount());
    await _local.transaction(() async {
      final existing = await _local.readRow(table, id);
      final pending = await _local.pendingFor(table, id);
      await _local.deleteRow(table, id);
      if (existing == null && pending == null) return;
      await _queue(
        Outbox.coalesce(
          pending: pending,
          newId: await _local.nextOutboxId(),
          table: table,
          rowId: id,
          op: OutboxOp.delete,
          payload: const {},
          changedFields: const {},
          baseRev: existing?.baseRev,
        ),
      );
    });
    await _publishCounts();
    if (syncOnWrite) unawaited(requestSync(force: true));
  }

  Future<void> _queue(Coalesced c) => switch (c) {
    Enqueue(:final entry) => _local.putEntry(entry),
    Cancel(:final entryId) => _local.removeEntry(entryId),
  };

  static const Set<String> _serverOwned = {
    SyncFields.rev,
    SyncFields.updatedAt,
  };

  static Map<String, Object?> _clientFields(Map<String, Object?> row) => {
    for (final e in row.entries)
      if (!_serverOwned.contains(e.key)) e.key: e.value,
  };

  // --------------------------------------------------------------- account

  String _requireAccount() {
    final account = _account();
    if (account == null) throw StateError('No signed-in account');
    return account;
  }

  /// Makes the store belong to [account]: if it holds another account's data,
  /// all of it (rows, outbox, cursors) is erased first, atomically — one
  /// user's queued edits must never be pushed under another user's session.
  Future<void> _adoptAccount(String account) async {
    if (await _local.account() == account) return;
    await _local.transaction(() async {
      await _local.clearAll();
      await _local.setAccount(account);
    });
  }

  /// Erases everything this device holds for the signed-in account.
  Future<void> signOut() async {
    await _local.transaction(() async {
      await _local.clearAll();
      await _local.setAccount(null);
    });
    _emit(SyncStatus.initial.copyWith(phase: SyncPhase.signedOut));
  }

  /// Call after re-authenticating from [SyncPhase.needsAuth].
  Future<void> resume() {
    _emit(_status.copyWith(phase: SyncPhase.idle, clearError: true));
    return requestSync(force: true);
  }

  // ------------------------------------------------------------ scheduling

  /// Runs a sync now, or — if one is running — makes sure another runs right
  /// after it. The returned future completes when a sync that started after
  /// this call has finished.
  Future<void> requestSync({bool force = false}) {
    final running = _running;
    if (running != null) {
      return (_rerun ??= Completer<void>()).future;
    }
    final last = _lastRunStarted;
    if (!force && last != null && _now().difference(last) < minInterval) {
      return Future.value();
    }
    return _start();
  }

  Future<void> _start() {
    final run = _runLoop();
    _running = run;
    return run;
  }

  Future<void> _runLoop() async {
    try {
      do {
        final rerun = _rerun;
        _rerun = null;
        _lastRunStarted = _now();
        await _syncOnce();
        rerun?.complete();
      } while (_rerun != null);
    } finally {
      _running = null;
    }
  }

  /// Starts periodic reconciliation (connectivity, resume and live pokes
  /// should also call [requestSync]).
  void start({Duration every = const Duration(minutes: 5)}) {
    _periodic?.cancel();
    _periodic = Timer.periodic(every, (_) => unawaited(requestSync()));
    unawaited(requestSync(force: true));
  }

  Future<void> dispose() async {
    _periodic?.cancel();
    await _running;
    await _statusController.close();
  }

  /// One push-then-pull pass. Public for tests and "sync now" buttons.
  Future<void> sync() => requestSync(force: true);

  Future<void> _syncOnce() async {
    final account = _account();
    if (account == null) {
      _emit(_status.copyWith(phase: SyncPhase.signedOut));
      return;
    }
    if (_status.phase == SyncPhase.needsAuth) return;
    await _adoptAccount(account);

    _emit(_status.copyWith(phase: SyncPhase.pushing, clearError: true));
    final pushed = await _push();
    if (pushed) {
      _emit(_status.copyWith(phase: SyncPhase.pulling));
      final pulled = await _pull(account);
      if (pulled) {
        _emit(_status.copyWith(phase: SyncPhase.idle, lastSyncedAt: _now()));
      }
    }
    await _publishCounts();
  }

  // ------------------------------------------------------------------ push

  /// Returns false when the pass must stop (offline, signed out, throttled).
  Future<bool> _push() async {
    final now = _now().millisecondsSinceEpoch;
    final due =
        (await _local.entries())
            .where((e) => e.state == OutboxState.pending)
            .where((e) => e.notBefore == null || e.notBefore! <= now)
            .toList()
          ..sort((a, b) {
            final byTable = _order(a.table).compareTo(_order(b.table));
            return byTable != 0 ? byTable : a.id.compareTo(b.id);
          });

    // A table whose push failed (retryably) blocks its descendants for this
    // pass, so a child is never sent before the parent row exists.
    final blocked = <String>{};
    for (final entry in due) {
      final table = _table(entry.table);
      if (!table.pushes) {
        await _local.removeEntry(entry.id);
        continue;
      }
      if (_hasBlockedAncestor(table, blocked)) continue;
      try {
        await _pushOne(table, entry);
      } on SyncRemoteException catch (e) {
        switch (e.kind) {
          case FailureKind.offline:
            _emit(
              _status.copyWith(phase: SyncPhase.offline, lastError: e.message),
            );
            return false;
          case FailureKind.unauthorized:
            _emit(
              _status.copyWith(
                phase: SyncPhase.needsAuth,
                lastError: e.message,
              ),
            );
            return false;
          case FailureKind.rateLimited:
            await _defer(
              entry,
              e.retryAfter ?? _retry.delayAfter(1),
              spend: false,
            );
            _emit(_status.copyWith(lastError: e.message));
            return false;
          case FailureKind.forbidden || FailureKind.invalid:
            await _deadLetter(entry, e);
          case FailureKind.exists ||
              FailureKind.revisionConflict ||
              FailureKind.notFound ||
              FailureKind.server:
            blocked.add(table.name);
            await _defer(entry, null, spend: true, error: e);
        }
      }
    }
    return true;
  }

  bool _hasBlockedAncestor(SyncTable table, Set<String> blocked) {
    for (final p in table.parents) {
      if (blocked.contains(p) || _hasBlockedAncestor(_table(p), blocked)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _pushOne(SyncTable table, OutboxEntry entry) async {
    switch (entry.op) {
      case OutboxOp.upsert when entry.isCreate:
        try {
          final row = await _remote.create(table.name, entry.payload);
          await _settle(entry, row);
        } on SyncRemoteException catch (e) {
          if (e.kind != FailureKind.exists) rethrow;
          // Same id already on the server: our own earlier create whose
          // response was lost, or a deterministic id another device created.
          final server =
              e.current ?? await _remote.read(table.name, entry.rowId);
          if (server == null) rethrow;
          await _reconcile(
            table,
            entry,
            server,
            changed: entry.payload.keys.toSet(),
          );
        }
      case OutboxOp.upsert:
        try {
          final changes = {
            for (final f in entry.changedFields)
              if (entry.payload.containsKey(f)) f: entry.payload[f],
          };
          final row = await _remote.update(
            table.name,
            entry.rowId,
            changes.isEmpty ? entry.payload : changes,
            ifRev: entry.baseRev!,
          );
          await _settle(entry, row);
        } on SyncRemoteException catch (e) {
          if (e.kind != FailureKind.revisionConflict &&
              e.kind != FailureKind.notFound) {
            rethrow;
          }
          final server =
              e.current ?? await _remote.read(table.name, entry.rowId);
          if (server == null) {
            await _gone(entry);
            return;
          }
          await _reconcile(table, entry, server, changed: entry.changedFields);
        }
      case OutboxOp.delete:
        if (entry.isCreate) {
          await _local.removeEntry(entry.id);
          return;
        }
        try {
          final row = await _remote.update(table.name, entry.rowId, {
            SyncFields.deletedAt: _now().millisecondsSinceEpoch,
          }, ifRev: entry.baseRev!);
          await _settle(entry, row);
        } on SyncRemoteException catch (e) {
          if (e.kind != FailureKind.revisionConflict &&
              e.kind != FailureKind.notFound) {
            rethrow;
          }
          final server =
              e.current ?? await _remote.read(table.name, entry.rowId);
          if (server == null || server.isDeleted) {
            await _gone(entry);
            return;
          }
          if (table.conflict is ServerWins) {
            // The server's newer edit beats our delete: the row comes back.
            await _acceptServer(entry, server);
          } else {
            final row = await _remote.update(table.name, entry.rowId, {
              SyncFields.deletedAt: _now().millisecondsSinceEpoch,
            }, ifRev: server.rev);
            await _settle(entry, row);
          }
        }
    }
  }

  /// The server row moved past our base (or already existed): decide by the
  /// table's policy, then write the resolution back conditioned on the
  /// server's CURRENT revision. Loops a few times if the row keeps moving.
  Future<void> _reconcile(
    SyncTable table,
    OutboxEntry entry,
    RemoteRow server, {
    required Set<String> changed,
  }) async {
    var current = server;
    for (var attempt = 0; attempt < 3; attempt++) {
      final resolution = _resolve(table.conflict, entry, current, changed);
      if (resolution == null) {
        await _acceptServer(entry, current);
        return;
      }
      try {
        final row = await _remote.update(
          table.name,
          entry.rowId,
          resolution,
          ifRev: current.rev,
        );
        await _settle(entry, row);
        return;
      } on SyncRemoteException catch (e) {
        if (e.kind != FailureKind.revisionConflict) rethrow;
        final next = e.current ?? await _remote.read(table.name, entry.rowId);
        if (next == null) {
          await _gone(entry);
          return;
        }
        current = next;
      }
    }
    throw const SyncRemoteException(
      FailureKind.server,
      message: 'row kept changing while resolving a conflict',
    );
  }

  Map<String, Object?>? _resolve(
    ConflictPolicy policy,
    OutboxEntry entry,
    RemoteRow server,
    Set<String> changed,
  ) {
    final local = entry.payload;
    final base = switch (policy) {
      ServerWins() => null,
      ClientWins() => {
        for (final e in local.entries)
          if (e.key != SyncFields.id) e.key: e.value,
      },
      FieldMerge() => {
        for (final f in changed)
          if (local.containsKey(f) && f != SyncFields.id) f: local[f],
      },
      CustomMerge(:final resolve) => resolve(
        local: local,
        server: server,
        changedFields: changed,
      ),
    };
    if (base == null) return null;
    // A tombstoned server row is resurrected by a winning local edit.
    return server.isDeleted ? {...base, SyncFields.deletedAt: null} : base;
  }

  /// The server's row is authoritative: adopt it locally and drop the change,
  /// unless a newer local write arrived meanwhile (then rebase that onto it).
  Future<void> _acceptServer(OutboxEntry entry, RemoteRow server) =>
      _local.transaction(() async {
        final latest = await _local.entry(entry.id);
        if (latest != null && latest.version != entry.version) {
          await _local.putEntry(latest.copyWith(baseRev: server.rev));
          await _local.setBaseRev(entry.table, entry.rowId, server.rev);
          return;
        }
        await _local.removeEntry(entry.id);
        await _local.applyRemote(entry.table, server);
      });

  /// The row no longer exists (or is no longer visible) on the server.
  Future<void> _gone(OutboxEntry entry) => _local.transaction(() async {
    await _local.removeEntry(entry.id);
    await _local.deleteRow(entry.table, entry.rowId);
  });

  /// A push succeeded with [row] as the server's result.
  Future<void> _settle(OutboxEntry entry, RemoteRow row) =>
      _local.transaction(() async {
        final latest = await _local.entry(entry.id);
        if (latest != null && latest.version != entry.version) {
          // The user edited again while this push was in flight: keep the
          // newer change, now based on the revision we just created.
          await _local.putEntry(latest.copyWith(baseRev: row.rev));
          await _local.setBaseRev(entry.table, entry.rowId, row.rev);
          return;
        }
        await _local.removeEntry(entry.id);
        if (row.isDeleted) {
          await _local.deleteRow(entry.table, entry.rowId);
        } else {
          await _local.applyRemote(entry.table, row);
        }
      });

  Future<void> _defer(
    OutboxEntry entry,
    Duration? wait, {
    required bool spend,
    SyncRemoteException? error,
  }) async {
    final attempts = entry.attempts + (spend ? 1 : 0);
    if (spend && attempts >= _retry.maxAttempts) {
      await _deadLetter(entry.copyWith(attempts: attempts), error);
      return;
    }
    final delay = wait ?? _retry.delayAfter(attempts);
    final latest = await _local.entry(entry.id);
    if (latest == null || latest.version != entry.version) return;
    await _local.putEntry(
      entry.copyWith(
        attempts: attempts,
        lastError: error?.toString(),
        notBefore: _now().add(delay).millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _deadLetter(OutboxEntry entry, SyncRemoteException? e) async {
    final latest = await _local.entry(entry.id);
    if (latest == null || latest.version != entry.version) return;
    await _local.putEntry(
      entry.copyWith(state: OutboxState.dead, lastError: e?.toString()),
    );
  }

  /// Puts a dead letter back in the queue.
  Future<void> retryDeadLetter(int entryId) async {
    final e = await _local.entry(entryId);
    if (e == null) return;
    await _local.putEntry(
      e.copyWith(state: OutboxState.pending, attempts: 0, clearNotBefore: true),
    );
    await _publishCounts();
    unawaited(requestSync(force: true));
  }

  /// Abandons a dead letter and restores the row to what the server has.
  Future<void> discardDeadLetter(int entryId) async {
    final e = await _local.entry(entryId);
    if (e == null) return;
    final server = await _remote.read(e.table, e.rowId);
    await _local.transaction(() async {
      await _local.removeEntry(entryId);
      if (server == null || server.isDeleted) {
        await _local.deleteRow(e.table, e.rowId);
      } else {
        await _local.applyRemote(e.table, server);
      }
    });
    await _publishCounts();
  }

  // ------------------------------------------------------------------ pull

  Future<bool> _pull(String account) async {
    for (final table in _tables.where((t) => t.pulls)) {
      final scope = table.scopeColumn == null
          ? null
          : SyncScope(table.scopeColumn!, account);
      var cursor = await _local.cursor(table.name);
      try {
        while (true) {
          final page = await _remote.pull(
            table.name,
            scope: scope,
            after: cursor,
            limit: pageSize,
          );
          if (page.rows.isEmpty) break;
          await _local.transaction(() async {
            for (final row in page.rows) {
              // A row with a local change still queued is left alone: the
              // push resolves it against the server by revision.
              if (await _local.pendingFor(table.name, row.id) != null) continue;
              await _local.applyRemote(table.name, row);
            }
            cursor = page.rows.last.cursor;
            await _local.setCursor(table.name, cursor!);
          });
          if (!page.hasMore) break;
        }
      } on SyncRemoteException catch (e) {
        switch (e.kind) {
          case FailureKind.offline:
            _emit(
              _status.copyWith(phase: SyncPhase.offline, lastError: e.message),
            );
            return false;
          case FailureKind.unauthorized:
            _emit(
              _status.copyWith(
                phase: SyncPhase.needsAuth,
                lastError: e.message,
              ),
            );
            return false;
          case _:
            // One table failing must not starve the others.
            _emit(_status.copyWith(lastError: '${table.name}: $e'));
        }
      }
    }
    return true;
  }

  // ---------------------------------------------------------------- status

  Future<void> _publishCounts() async {
    final all = await _local.entries();
    _emit(
      _status.copyWith(
        pending: all.where((e) => e.state == OutboxState.pending).length,
        deadLetters: all.where((e) => e.state == OutboxState.dead).toList(),
      ),
    );
  }

  void _emit(SyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}
