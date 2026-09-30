import 'package:zonai_sync/zonai_sync.dart';

/// An in-memory server with zonai v0.9.4's semantics where they matter to
/// sync — each of which bit a hand-written engine:
///
/// * the server stamps `updated_at` from ITS clock and bumps `rev`; client
///   values for either are ignored;
/// * a list fails WHOLE with 403 if any returned row is not visible to the
///   caller (rules/overview.md:41) — so unscoped pulls break;
/// * a create with an existing id is a 409;
/// * with [tableLevelUpdateCheck], an update of a row that does not exist is
///   refused 403 BEFORE the lookup, as table-level rules do — so an engine
///   that does update-then-create on a new row never gets to create.
final class FakeZonai implements SyncRemote {
  FakeZonai({this.ownerColumn = 'owner_id', this.tableLevelUpdateCheck = true});

  final String ownerColumn;
  final bool tableLevelUpdateCheck;

  final tables = <String, Map<String, Map<String, Object?>>>{};

  /// The authenticated caller (a JWT's user id).
  String? user = 'u1';
  int clock = 1000;
  bool offline = false;

  /// Failures to throw from the next calls, in order (any error, not only
  /// SyncRemoteException — engines must survive a bug-shaped throw too).
  final failures = <Object>[];

  /// Runs while a call is "on the wire", before the server acts on it, so a
  /// test can interleave local work with an in-flight request.
  Future<void> Function(String call)? whileInFlight;

  /// Every call that reached the server, for asserting on what the engine did.
  final calls = <String>[];

  Future<void> _gate(String call) async {
    await whileInFlight?.call(call);
    if (offline) {
      throw const SyncRemoteException(FailureKind.offline, message: 'offline');
    }
    if (user == null) {
      throw const SyncRemoteException(FailureKind.unauthorized);
    }
    if (failures.isNotEmpty)
      throw failures.removeAt(0); // ignore: only_throw_errors
    // Recorded only once the request would have reached the server.
    calls.add(call);
  }

  int _tick() => ++clock;

  bool _visible(Map<String, Object?> row) => row[ownerColumn] == user;

  Map<String, Map<String, Object?>> _t(String table) => tables[table] ??= {};

  /// Writes as another client would (server-side edit, other device, etc).
  RemoteRow serverWrite(String table, Map<String, Object?> row) {
    final id = row['id']! as String;
    final existing = _t(table)[id];
    final next = {
      ...?existing,
      ...row,
      'rev': ((existing?['rev'] as int?) ?? 0) + 1,
      'updated_at': _tick(),
    };
    _t(table)[id] = next;
    return RemoteRow(Map.of(next));
  }

  @override
  Future<RemoteRow> create(String table, Map<String, Object?> row) async {
    await _gate('create $table/${row['id']}');
    final id = row['id']! as String;
    final existing = _t(table)[id];
    if (existing != null) {
      throw SyncRemoteException(
        FailureKind.exists,
        current: _visible(existing) ? RemoteRow(Map.of(existing)) : null,
      );
    }
    if (!_visible(row)) throw const SyncRemoteException(FailureKind.forbidden);
    final stored = {
      ...row,
      'rev': 1,
      'updated_at': _tick(), // non-null on insert: the column is server-owned
      'deleted_at': row['deleted_at'],
    };
    _t(table)[id] = stored;
    return RemoteRow(Map.of(stored));
  }

  @override
  Future<RemoteRow> update(
    String table,
    String id,
    Map<String, Object?> changes, {
    required int ifRev,
  }) async {
    await _gate('update $table/$id @$ifRev');
    final existing = _t(table)[id];
    if (existing == null) {
      throw SyncRemoteException(
        tableLevelUpdateCheck ? FailureKind.forbidden : FailureKind.notFound,
      );
    }
    if (!_visible(existing)) {
      throw const SyncRemoteException(FailureKind.forbidden);
    }
    if (existing['rev'] != ifRev) {
      throw SyncRemoteException(
        FailureKind.revisionConflict,
        current: RemoteRow(Map.of(existing)),
      );
    }
    final next = {
      ...existing,
      for (final e in changes.entries)
        if (e.key != 'rev' && e.key != 'updated_at') e.key: e.value,
      'rev': (existing['rev']! as int) + 1,
      'updated_at': _tick(),
    };
    _t(table)[id] = next;
    return RemoteRow(Map.of(next));
  }

  @override
  Future<RemoteRow?> read(String table, String id) async {
    await _gate('read $table/$id');
    final row = _t(table)[id];
    if (row == null || !_visible(row)) return null;
    return RemoteRow(Map.of(row));
  }

  /// How many pulls were made without a scope.
  int unscopedPulls = 0;

  @override
  Future<PullPage> pull(
    String table, {
    required SyncScope? scope,
    required SyncCursor? after,
    required int limit,
  }) async {
    await _gate('pull $table');
    if (scope == null) unscopedPulls++;
    final rows =
        _t(table).values
            .where((r) => scope == null || r[scope.column] == scope.value)
            .where((r) {
              if (after == null) return true;
              final u = r['updated_at']! as int;
              return u > after.updatedAt ||
                  (u == after.updatedAt &&
                      (r['id']! as String).compareTo(after.id) > 0);
            })
            .toList()
          ..sort((a, b) {
            final byTime = (a['updated_at']! as int).compareTo(
              b['updated_at']! as int,
            );
            return byTime != 0
                ? byTime
                : (a['id']! as String).compareTo(b['id']! as String);
          });
    if (rows.any((r) => !_visible(r))) {
      throw const SyncRemoteException(
        FailureKind.forbidden,
        message: 'a row in the list failed canView',
      );
    }
    final page = rows.take(limit).map((r) => RemoteRow(Map.of(r))).toList();
    return PullPage(rows: page, hasMore: rows.length > limit);
  }
}
