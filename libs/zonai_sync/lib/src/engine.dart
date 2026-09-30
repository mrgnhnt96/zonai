import 'dart:async';

import 'package:zonai_sync/src/cursor.dart';
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
    this.pullOverlap = const Duration(seconds: 2),
    this.claimUnownedData = true,
    this.guestIds,
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

  /// When the first account signs in on a device that was used without one,
  /// keep the existing local rows and upload them to that account (the
  /// default), instead of erasing them. A store that already belongs to
  /// another account is always cleared.
  ///
  /// Only a NEVER-used store is claimed. Once any account has signed out,
  /// the device never claims again: anything the app writes into the store
  /// directly while signed out is erased at the next sign-in, like any other
  /// leftover of a previous account.
  final bool claimUnownedData;

  /// The pre-account guest ids (an anonymous session, say) that belong to
  /// the account now signing in, which is passed in.
  ///
  /// At a claim, rows whose owner column names someone else are left alone
  /// (kept, unsynced, counted in [SyncStatus.unclaimed]) unless their owner is
  /// one of these ids; those are re-owned to the account and uploaded.
  ///
  /// It is a list of ids, not a predicate, on purpose: a store can hold a
  /// REAL user's rows (a database migrated from a hand-built engine, a
  /// restored backup), and a predicate like `(_) => true` would upload them
  /// under whoever signs in next. Return only ids you know this account
  /// created.
  ///
  /// It is consulted at the first sign-in's claim, and again whenever
  /// [claimGuestRows] is called (for an app that learns a guest id later).
  final Set<String> Function(String account)? guestIds;

  /// How far behind its stored cursor each pull starts re-reading.
  ///
  /// `updated_at` is stamped by the server when it builds a write, so rows can
  /// commit out of stamp order — with several HTTP isolates, or when the
  /// server clock steps back — and a strict "after the cursor" pull would
  /// skip them forever. Re-reading a short window catches them; re-applying a
  /// row already held is harmless. A server-assigned sequence column removes
  /// the need (set this to zero then).
  final Duration pullOverlap;

  /// Non-forced [requestSync] calls closer together than this are coalesced.
  final Duration minInterval;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = SyncStatus.initial;
  Future<void>? _running;
  Completer<void>? _rerun;
  DateTime? _lastRunStarted;
  Timer? _periodic;

  /// The account the running pass works for. Every step that applies server
  /// data checks the store still belongs to it: a sign-out or account switch
  /// mid-pass must not let the old account's rows back in.
  String? _passAccount;

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
    final account = _requireAccount();
    await _adoptAccount(account);
    await _local.transaction(() async {
      await _ensureStoreOwnedBy(account);
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
    final account = _requireAccount();
    await _adoptAccount(account);
    await _local.transaction(() async {
      await _ensureStoreOwnedBy(account);
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
    // Fast path only; the decision below re-reads the owner INSIDE the
    // transaction, since it may change between this read and that one.
    if (await _local.account() == account) return;
    var changedHands = false;
    await _local.transaction(() async {
      final owner = await _local.account();
      if (owner == account) return;
      changedHands = true;
      // Only a device NO account has ever used may be claimed. After a
      // sign-out the store holds [signedOutMarker], not null, so whatever is
      // left over can never be handed to the next account.
      if (owner == null && claimUnownedData) {
        // Nobody has signed in on this device before: whatever exists was
        // made by this user before they had an account. Keep it, and queue
        // every row so it reaches their account.
        await _claimLocalRows(account);
      } else {
        await _local.clearAll();
      }
      await _local.setAccount(account);
    });
    // Counted once the claim or clear has COMMITTED; a rolled-back claim
    // throws out of the transaction above and counts nothing.
    if (changedHands) await _refreshUnclaimed(account);
  }

  /// Returns how many rows it queued.
  Future<int> _claimLocalRows(String account, {bool onlyGuests = false}) async {
    var claimed = 0;
    final guests = guestIds?.call(account) ?? const <String>{};
    for (final table in _tables.where((t) => t.pushes)) {
      for (final id in await _local.rowIds(table.name)) {
        if (await _local.pendingFor(table.name, id) != null) continue;
        final existing = await _local.readRow(table.name, id);
        // A row with a base revision has been on the server, owned by
        // whoever it names: never re-owned, whatever guestIds says.
        if (existing == null || existing.baseRev != null) continue;
        final scope = table.scopeColumn;
        final named = scope == null ? null : existing.data[scope];
        final guest = named is String && guests.contains(named);
        if (onlyGuests
            ? !guest
            : named is String && named != account && !guest) {
          // It names someone else: never upload it under this account, and
          // never delete it either — keep it, unsynced, for the app.
          continue;
        }
        // Rows made before there was an account have no owner yet.
        final data = {
          ...existing.data,
          if (table.scopeColumn != null) table.scopeColumn!: account,
        };
        await _local.writeRow(table.name, data);
        final row = LocalRow(data: data, baseRev: existing.baseRev);
        await _queue(
          Outbox.coalesce(
            pending: null,
            newId: await _local.nextOutboxId(),
            table: table.name,
            rowId: id,
            op: OutboxOp.upsert,
            payload: _clientFields(row.data),
            changedFields: row.data.keys.toSet()..removeAll(_serverOwned),
            baseRev: row.baseRev,
          ),
        );
        claimed++;
      }
    }
    return claimed;
  }

  /// Re-owns and uploads rows whose owner is one of [guestIds] for the
  /// signed-in account, after the first sign-in's claim has run. Returns how
  /// many rows were claimed.
  Future<int> claimGuestRows() async {
    final account = _requireAccount();
    await _adoptAccount(account);
    var claimed = 0;
    await _local.transaction(() async {
      await _ensureStoreOwnedBy(account);
      claimed = await _claimLocalRows(account, onlyGuests: true);
    });
    await _refreshUnclaimed(account);
    await _publishCounts();
    if (claimed > 0 && syncOnWrite) unawaited(requestSync(force: true));
    return claimed;
  }

  /// Whether [SyncStatus.unclaimed] reflects the store yet. It is counted
  /// from the store, never carried in memory: a restart, an account switch
  /// that clears the rows, or a claim that rolled back would each leave a
  /// remembered figure wrong.
  bool _unclaimedCounted = false;

  Future<void> _refreshUnclaimed(String account) async {
    var unclaimed = 0;
    for (final table in _tables.where((t) => t.pushes)) {
      final scope = table.scopeColumn;
      if (scope == null) continue;
      for (final id in await _local.rowIds(table.name)) {
        final named = (await _local.readRow(table.name, id))?.data[scope];
        if (named is String &&
            named != account &&
            await _local.pendingFor(table.name, id) == null) {
          unclaimed++;
        }
      }
    }
    _unclaimedCounted = true;
    _emit(_status.copyWith(unclaimed: unclaimed));
  }

  /// Stored as the account after [signOut]: "used before, owned by no one
  /// now". Distinct from null ("never used"), which is the only state whose
  /// leftover data may be claimed by the next account.
  static const signedOutMarker = '\u0000signed-out';

  /// Throws [StateError] unless the store currently belongs to [account]:
  /// a sign-out or account switch landed between a caller's account check
  /// and its transaction, and the write must not commit into a store that
  /// was just cleared for someone else.
  Future<void> _ensureStoreOwnedBy(String account) async {
    if (await _local.account() != account) {
      throw StateError('The signed-in account changed during this write');
    }
  }

  /// Erases everything this device holds for the signed-in account.
  Future<void> signOut() async {
    await _local.transaction(() async {
      await _local.clearAll();
      await _local.setAccount(signedOutMarker);
    });
    _unclaimedCounted = false;
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
        try {
          await _syncOnce();
        } on _AccountChanged {
          // The account changed mid-pass; its work was abandoned on purpose.
          // The status must not stay on the phase the pass was in.
          _emit(
            _status.copyWith(
              phase: _account() == null ? SyncPhase.signedOut : SyncPhase.idle,
            ),
          );
        } on Object catch (e) {
          // A bug-shaped failure (a store error, a malformed row) ends this
          // pass, is reported, and must not strand callers waiting on it.
          _emit(_status.copyWith(phase: SyncPhase.idle, lastError: '$e'));
        } finally {
          _passAccount = null;
          rerun?.complete();
        }
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
    if (!_unclaimedCounted) await _refreshUnclaimed(account);
    _passAccount = account;

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

    // A table with a change still waiting to reach the server blocks its
    // descendants, so a child is never sent before its parent row exists
    // (zonai answers a missing FK parent with 422, which would dead-letter
    // the child for good). That covers parents backing off from an earlier
    // pass as well as ones failing in this pass.
    // Dead parents block too: their children would only earn a 422.
    final all = await _local.entries();
    final stuck = <(String, String)>{
      for (final e in all)
        if (e.state == OutboxState.dead ||
            (e.notBefore != null && e.notBefore! > now))
          (e.table, e.rowId),
    };
    // Table-level holds (tables without `references`) come only from
    // TRANSIENT trouble; a dead parent row surfaces as its child's own
    // failure instead of freezing the whole child table.
    final blocked = {
      for (final e in all)
        if (e.state == OutboxState.pending &&
            e.notBefore != null &&
            e.notBefore! > now)
          e.table,
    };
    for (final entry in due) {
      final table = _table(entry.table);
      if (!table.pushes) {
        await _local.removeEntry(entry.id);
        continue;
      }
      if (_isHeldBack(table, entry, stuck, blocked)) {
        // Held rows hold THEIR children too (a grade waits for a student
        // that waits for a dead course), row by row through `references`.
        // They do NOT table-block a child table without references: when the
        // cause is a waiting row, its own table is already blocked and the
        // ancestor walk holds every descendant table; when the cause is a
        // dead row, a table block would freeze unrelated rows until a human
        // acts (see README, "Parents and children").
        stuck.add((entry.table, entry.rowId));
        continue;
      }
      // Every entry is re-checked: an account switch mid-pass must stop the
      // rest of the OLD account's queue from going out under the new session.
      await _ensureOwner();
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
            stuck.add((entry.table, entry.rowId));
          case FailureKind.exists ||
              FailureKind.revisionConflict ||
              FailureKind.notFound ||
              FailureKind.server:
            blocked.add(table.name);
            stuck.add((entry.table, entry.rowId));
            await _defer(entry, null, spend: true, error: e);
        }
      }
    }
    return true;
  }

  /// Whether [entry] must wait for a parent. A parent named in
  /// [SyncTable.references] holds it per row (only its own parent row being
  /// stuck); any other parent holds it table-level (a waiting row anywhere in
  /// that ancestor table).
  bool _isHeldBack(
    SyncTable table,
    OutboxEntry entry,
    Set<(String, String)> stuck,
    Set<String> blocked,
  ) {
    for (final MapEntry(key: column, value: parent)
        in table.references.entries) {
      final parentId = entry.payload[column];
      if (parentId is String && stuck.contains((parent, parentId))) {
        return true;
      }
    }
    // Parents no reference covers are held table-level, as without any.
    final covered = table.references.values.toSet();
    for (final p in table.parents) {
      if (covered.contains(p)) continue;
      if (blocked.contains(p) || _hasBlockedAncestor(_table(p), blocked)) {
        return true;
      }
    }
    return false;
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
        if (!entry.sent) await _markSent(entry);
        try {
          final row = await _net((r) => r.create(table.name, entry.payload));
          await _settle(entry, row);
        } on SyncRemoteException catch (e) {
          if (e.kind != FailureKind.exists) rethrow;
          // Same id already on the server: our own earlier create whose
          // response was lost, or a deterministic id another device created.
          final server =
              e.current ?? await _net((r) => r.read(table.name, entry.rowId));
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
          final row = await _net(
            (r) => r.update(
              table.name,
              entry.rowId,
              changes.isEmpty ? entry.payload : changes,
              ifRev: entry.baseRev!,
            ),
          );
          await _settle(entry, row);
        } on SyncRemoteException catch (e) {
          if (e.kind != FailureKind.revisionConflict &&
              e.kind != FailureKind.notFound) {
            rethrow;
          }
          final server =
              e.current ?? await _net((r) => r.read(table.name, entry.rowId));
          if (server == null) {
            await _gone(entry);
            return;
          }
          await _reconcile(table, entry, server, changed: entry.changedFields);
        }
      case OutboxOp.delete when entry.isCreate:
        // A delete of a row whose create was SENT but never confirmed: the
        // server may hold it. Tombstone whatever is there.
        final server = entry.sent
            ? await _net((r) => r.read(table.name, entry.rowId))
            : null;
        if (server == null || server.isDeleted) {
          await _gone(entry);
          return;
        }
        final row = await _net(
          (r) => r.update(table.name, entry.rowId, {
            SyncFields.deletedAt: _now().millisecondsSinceEpoch,
          }, ifRev: server.rev),
        );
        await _settle(entry, row);
      case OutboxOp.delete:
        try {
          final row = await _net(
            (r) => r.update(table.name, entry.rowId, {
              SyncFields.deletedAt: _now().millisecondsSinceEpoch,
            }, ifRev: entry.baseRev!),
          );
          await _settle(entry, row);
        } on SyncRemoteException catch (e) {
          if (e.kind != FailureKind.revisionConflict &&
              e.kind != FailureKind.notFound) {
            rethrow;
          }
          final server =
              e.current ?? await _net((r) => r.read(table.name, entry.rowId));
          if (server == null || server.isDeleted) {
            await _gone(entry);
            return;
          }
          if (table.conflict is ServerWins) {
            // The server's newer edit beats our delete: the row comes back.
            await _acceptServer(entry, server);
          } else {
            final row = await _net(
              (r) => r.update(table.name, entry.rowId, {
                SyncFields.deletedAt: _now().millisecondsSinceEpoch,
              }, ifRev: server.rev),
            );
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
        final row = await _net(
          (r) =>
              r.update(table.name, entry.rowId, resolution, ifRev: current.rev),
        );
        await _settle(entry, row);
        return;
      } on SyncRemoteException catch (e) {
        if (e.kind != FailureKind.revisionConflict) rethrow;
        final next =
            e.current ?? await _net((r) => r.read(table.name, entry.rowId));
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

  /// Throws [_AccountChanged] when the store no longer belongs to the account
  /// this pass started for. Called first inside every transaction that
  /// applies server data.
  Future<void> _ensureOwner() => _ensureOwnerIs(_passAccount);

  /// The live account is checked again AFTER the store read: a switch that
  /// lands while that read is in flight must still stop the request, and
  /// nothing may await between this and the call it guards.
  Future<void> _ensureOwnerIs(String? owner) async {
    if (owner == null ||
        _account() != owner ||
        await _local.account() != owner ||
        _account() != owner) {
      throw const _AccountChanged();
    }
  }

  /// Every network call a pass makes goes through here, so the owner is
  /// checked against the app's LIVE account immediately before the request
  /// leaves — not only when the pass began, or when a result is applied.
  Future<T> _net<T>(Future<T> Function(SyncRemote remote) call) async {
    await _ensureOwner();
    return call(_remote);
  }

  /// The server's row is authoritative: adopt it locally and drop the change,
  /// unless a newer local write arrived meanwhile (then rebase that onto it).
  Future<void> _acceptServer(OutboxEntry entry, RemoteRow server) =>
      _local.transaction(() async {
        await _ensureOwner();
        final latest = await _local.entry(entry.id);
        if (latest != null && latest.version != entry.version) {
          await _rebase(latest, server);
          return;
        }
        await _local.removeEntry(entry.id);
        await _local.applyRemote(entry.table, server);
      });

  /// Keeps a newer local change, now based on the server's [row]. An upsert
  /// rebased onto a TOMBSTONED row must also clear the tombstone, or the
  /// user's later write would land on a row that stays deleted.
  Future<void> _rebase(OutboxEntry latest, RemoteRow row) async {
    final revive = row.isDeleted && latest.op == OutboxOp.upsert;
    await _local.putEntry(
      latest.copyWith(
        baseRev: row.rev,
        payload: revive
            ? {...latest.payload, SyncFields.deletedAt: null}
            : null,
        changedFields: revive
            ? {...latest.changedFields, SyncFields.deletedAt}
            : null,
      ),
    );
    await _local.setBaseRev(latest.table, latest.rowId, row.rev);
  }

  /// The row no longer exists (or is no longer visible) on the server.
  Future<void> _gone(OutboxEntry entry) => _local.transaction(() async {
    await _ensureOwner();
    await _local.removeEntry(entry.id);
    await _local.deleteRow(entry.table, entry.rowId);
  });

  /// A push succeeded with [row] as the server's result.
  Future<void> _settle(OutboxEntry entry, RemoteRow row) =>
      _local.transaction(() async {
        await _ensureOwner();
        final latest = await _local.entry(entry.id);
        if (latest != null && latest.version != entry.version) {
          // The user edited again while this push was in flight: keep the
          // newer change, now based on the revision we just created.
          await _rebase(latest, row);
          return;
        }
        if (latest == null &&
            !row.isDeleted &&
            await _local.readRow(entry.table, entry.rowId) == null) {
          // The row was deleted locally while its create was on the wire:
          // the create cancelled out locally but landed on the server, so the
          // delete must follow it there.
          await _local.putEntry(
            OutboxEntry(
              id: await _local.nextOutboxId(),
              table: entry.table,
              rowId: entry.rowId,
              op: OutboxOp.delete,
              payload: const {},
              changedFields: const {},
              baseRev: row.rev,
              version: 1,
            ),
          );
          return;
        }
        await _local.removeEntry(entry.id);
        if (row.isDeleted) {
          await _local.deleteRow(entry.table, entry.rowId);
        } else {
          await _local.applyRemote(entry.table, row);
        }
      });

  /// Records that a create is about to be sent (see [OutboxEntry.sent]).
  Future<void> _markSent(OutboxEntry entry) => _local.transaction(() async {
    final latest = await _local.entry(entry.id);
    if (latest != null) await _local.putEntry(latest.copyWith(sent: true));
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
    await _local.transaction(() async {
      final latest = await _local.entry(entry.id);
      if (latest == null || latest.version != entry.version) return;
      await _local.putEntry(
        latest.copyWith(
          attempts: attempts,
          lastError: error?.toString(),
          notBefore: _now().add(delay).millisecondsSinceEpoch,
        ),
      );
    });
  }

  Future<void> _deadLetter(OutboxEntry entry, SyncRemoteException? e) =>
      _local.transaction(() async {
        final latest = await _local.entry(entry.id);
        if (latest == null || latest.version != entry.version) return;
        await _local.putEntry(
          latest.copyWith(
            state: OutboxState.dead,
            attempts: entry.attempts,
            lastError: e?.toString(),
          ),
        );
      });

  /// Puts a dead letter back in the queue.
  Future<void> retryDeadLetter(int entryId) async {
    await _local.transaction(() async {
      final e = await _local.entry(entryId);
      if (e == null || e.state != OutboxState.dead) return;
      await _local.putEntry(
        e.copyWith(
          state: OutboxState.pending,
          attempts: 0,
          clearNotBefore: true,
        ),
      );
    });
    await _publishCounts();
    unawaited(requestSync(force: true));
  }

  /// Abandons a dead letter and restores the row to what the server has.
  Future<void> discardDeadLetter(int entryId) async {
    final e = await _local.entry(entryId);
    final owner = _account();
    if (e == null || owner == null) return;
    final RemoteRow? server;
    try {
      // Outside a pass, so it checks the owner itself, exactly as _net does.
      await _ensureOwnerIs(owner);
      server = await _remote.read(e.table, e.rowId);
    } on _AccountChanged {
      return;
    }
    await _local.transaction(() async {
      // Anything may have happened while we read the server: a newer edit
      // (which replaced the dead letter) or a different account.
      final latest = await _local.entry(entryId);
      if (latest == null ||
          latest.version != e.version ||
          latest.state != OutboxState.dead ||
          await _local.account() != owner) {
        return;
      }
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
      final stored = await _local.cursor(table.name);
      var after = stored == null || pullOverlap == Duration.zero
          ? stored
          : SyncCursor(
              updatedAt: stored.updatedAt - pullOverlap.inMilliseconds,
              id: '',
            );
      try {
        while (true) {
          final page = await _net(
            (r) =>
                r.pull(table.name, scope: scope, after: after, limit: pageSize),
          );
          if (page.rows.isEmpty) break;
          await _local.transaction(() async {
            await _ensureOwner();
            for (final row in page.rows) {
              // A row with a local change still queued is left alone: the
              // push resolves it against the server by revision.
              if (await _local.pendingFor(table.name, row.id) != null) continue;
              await _local.applyRemote(table.name, row);
            }
            // The stored cursor only moves forward; the overlap re-read
            // never drags it back.
            final last = page.rows.last.cursor;
            final current = await _local.cursor(table.name);
            if (current == null || _after(last, current)) {
              await _local.setCursor(table.name, last);
            }
          });
          after = page.rows.last.cursor;
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

  static bool _after(SyncCursor a, SyncCursor b) =>
      a.updatedAt > b.updatedAt ||
      (a.updatedAt == b.updatedAt && a.id.compareTo(b.id) > 0);

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

/// The store changed hands mid-pass (sign-out, or another account signed in).
final class _AccountChanged implements Exception {
  const _AccountChanged();
}
