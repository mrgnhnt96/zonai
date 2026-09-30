import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:revali_client/revali_client.dart' show ServerException;
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_sync/src/cursor.dart';
import 'package:zonai_sync/src/remote.dart';

/// What the connected server supports. Everything defaults to what zonai
/// v0.9.4 does, so the adapter works today; flip a flag once the server
/// release that adds the feature is deployed.
final class ZonaiSyncCapabilities {
  const ZonaiSyncCapabilities({this.serverRevision = false});

  /// The server maintains `rev` itself (a `$.revision()` column) and refuses
  /// client writes to it. When false, the client increments `rev` inside the
  /// same conditional update, which is equally atomic on a single-writer
  /// SQLite server.
  final bool serverRevision;
}

/// [SyncRemote] over zonai's `/db` API.
///
/// Wire conventions it owns so apps don't have to: dates travel as epoch
/// milliseconds, rows are matched by `id`, revision checks are expressed as
/// conditional updates, and every failure is classified by HTTP status —
/// never by parsing a message.
final class ZonaiSyncRemote implements SyncRemote {
  ZonaiSyncRemote(
    this._client, {
    this.capabilities = const ZonaiSyncCapabilities(),
  });

  final ZonaiClient _client;
  final ZonaiSyncCapabilities capabilities;

  @override
  Future<RemoteRow> create(String table, Map<String, Object?> row) async {
    final object = {
      ...row,
      if (!capabilities.serverRevision) SyncFields.rev: 0,
    };
    try {
      final data = await _guard(
        () => _client.db.create(
          body: CreateBody(table: table, object: object),
          fromJson: (json) => json,
        ),
      );
      return _row(table, data);
    } on SyncRemoteException catch (e) {
      if (e.kind != FailureKind.exists) rethrow;
      // Hand the engine the row that holds this id, when we may see it.
      final current = await read(table, row[SyncFields.id]! as String);
      throw SyncRemoteException(
        FailureKind.exists,
        message: e.message,
        current: current,
      );
    }
  }

  @override
  Future<RemoteRow> update(
    String table,
    String id,
    Map<String, Object?> changes, {
    required int ifRev,
  }) async {
    final writable = {
      for (final e in changes.entries)
        if (e.key != SyncFields.id &&
            e.key != SyncFields.rev &&
            e.key != SyncFields.updatedAt)
          e.key: e.value,
    };
    try {
      final data = await _guard(
        () => _client.db.update(
          body: UpdateOneBody(
            table: table,
            where: And([Eq(SyncFields.id, id), Eq(SyncFields.rev, ifRev)]),
            updates: [
              Update.object(writable),
              if (!capabilities.serverRevision)
                Update.column(SyncFields.rev, UpdateValue.increment()),
            ],
          ),
          fromJson: (json) => json,
        ),
      );
      return _row(table, data);
    } on SyncRemoteException catch (e) {
      if (e.kind != FailureKind.notFound) rethrow;
      // Today's zonai answers a failed `rev = N` condition with 404, the same
      // as a missing row. Read it to tell the two apart.
      final current = await read(table, id);
      if (current == null) rethrow;
      if (current.rev != ifRev) {
        throw SyncRemoteException(
          FailureKind.revisionConflict,
          message: 'rev is ${current.rev}, expected $ifRev',
          current: current,
        );
      }
      throw SyncRemoteException(
        FailureKind.server,
        message: 'update of $table/$id matched nothing at rev $ifRev',
      );
    }
  }

  @override
  Future<RemoteRow?> read(String table, String id) async {
    try {
      final data = await _guard(
        () => _client.db.get(
          body: GetBody(table: table, where: Eq(SyncFields.id, id)),
          fromJson: (json) => json,
        ),
      );
      return _row(table, data);
    } on SyncRemoteException catch (e) {
      if (e.kind == FailureKind.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<PullPage> pull(
    String table, {
    required SyncScope? scope,
    required SyncCursor? after,
    required int limit,
  }) async {
    final conditions = <Where>[
      if (scope != null) Eq(scope.column, scope.value),
      if (after != null)
        Or([
          Gt(SyncFields.updatedAt, after.updatedAt),
          And([
            Eq(SyncFields.updatedAt, after.updatedAt),
            Gt(SyncFields.id, after.id),
          ]),
        ]),
    ];
    final page = await _guard(
      () => _client.db.list(
        body: ListBody(
          table: table,
          where: switch (conditions) {
            [] => null,
            [final only] => only,
            _ => And(conditions),
          },
          orderBy: const [
            OrderByTerm(column: SyncFields.updatedAt),
            OrderByTerm(column: SyncFields.id),
          ],
          limit: limit,
        ),
        fromJson: (json) => json,
      ),
    );
    return PullPage(
      rows: [for (final item in page.items) _row(table, item)],
      // zonai's list reports a total, not a has-more flag; a full page means
      // there may be more, and an empty next page ends the loop.
      hasMore: page.items.length >= limit,
    );
  }

  /// Normalises a server row: dates to epoch ms, and a clear error for a
  /// table the sync schema was not applied to.
  RemoteRow _row(String table, Map<String, Object?> data) {
    final normalised = {
      for (final e in data.entries)
        e.key: e.key == SyncFields.updatedAt || e.key == SyncFields.deletedAt
            ? _millis(e.value)
            : e.value,
    };
    if (normalised[SyncFields.updatedAt] == null) {
      throw StateError(
        '$table/${data[SyncFields.id]} has no updated_at. Synced tables need a '
        'NON-NULL, server-maintained updated_at (zonai_sync_schema\'s '
        '\$.syncColumns()): a nullable one is NULL on insert, and rows that '
        'are never updated would never be pulled.',
      );
    }
    return RemoteRow(normalised);
  }

  static int? _millis(Object? value) => switch (value) {
    null => null,
    final int ms => ms,
    final String iso => DateTime.parse(iso).millisecondsSinceEpoch,
    final DateTime d => d.millisecondsSinceEpoch,
    _ => throw FormatException('Not a timestamp: $value'),
  };

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ServerException catch (e) {
      throw classify(e.statusCode, message: e.message, body: e.body);
    } on SocketException catch (e) {
      throw SyncRemoteException(FailureKind.offline, message: e.message);
    } on http.ClientException catch (e) {
      throw SyncRemoteException(FailureKind.offline, message: e.message);
    } on TimeoutException catch (e) {
      throw SyncRemoteException(
        FailureKind.offline,
        message: e.message ?? 'timeout',
      );
    }
  }

  /// Maps an HTTP failure to what the engine should do about it.
  static SyncRemoteException classify(
    int status, {
    String message = '',
    String? body,
  }) {
    final details = _decode(body);
    return switch (status) {
      401 => SyncRemoteException(FailureKind.unauthorized, message: message),
      403 => SyncRemoteException(FailureKind.forbidden, message: message),
      404 => SyncRemoteException(FailureKind.notFound, message: message),
      409 => SyncRemoteException(FailureKind.exists, message: message),
      412 => SyncRemoteException(
        FailureKind.revisionConflict,
        message: message,
        current: _preconditionRow(details),
      ),
      429 => SyncRemoteException(
        FailureKind.rateLimited,
        message: message,
        retryAfter: switch (details?['retryAfter']) {
          final int s => Duration(seconds: s),
          _ => null,
        },
      ),
      400 || 422 => SyncRemoteException(FailureKind.invalid, message: message),
      _ => SyncRemoteException(FailureKind.server, message: '$status $message'),
    };
  }

  static Map<String, Object?>? _decode(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? json : null;
    } on FormatException {
      return null;
    }
  }

  /// The current row from a 412 body:
  /// `{error: {code: precondition_failed, details: {current: [row]}}}`.
  static RemoteRow? _preconditionRow(Map<String, Object?>? body) {
    final error = body?['error'];
    if (error is! Map) return null;
    final details = error['details'];
    if (details is! Map) return null;
    final current = details['current'];
    if (current is! List || current.isEmpty || current.first is! Map) {
      return null;
    }
    final row = (current.first as Map).cast<String, Object?>();
    return RemoteRow({
      ...row,
      SyncFields.updatedAt: _millis(row[SyncFields.updatedAt]),
      SyncFields.deletedAt: _millis(row[SyncFields.deletedAt]),
    });
  }
}
