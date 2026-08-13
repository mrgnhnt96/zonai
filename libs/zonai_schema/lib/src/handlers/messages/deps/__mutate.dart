part of '../message_handler.dart';

final _mutateProvider = create<_Mutate>(_Mutate._);
_Mutate get mutate => read(_mutateProvider);

class _Mutate {
  _Mutate({
    required _UpdateMany update,
    required _DeleteMany delete,
    required _CreateMany create,
    required _PurgeMany purge,
  }) {
    this.update = _Update(update);
    this.delete = _Delete(delete);
    this.create = _Create(create);
    this.purge = purge;
  }
  _Mutate._() {
    update = _Update(
      ({required String tableName, required updates, required where, limit}) {},
    );
    delete = _Delete(({required String tableName, required where, limit}) {});
    create = _Create(({required String tableName, required objects}) {});
    purge = ({required String tableName, required where}) async => 0;
  }

  late final _Update update;
  late final _Delete delete;
  late final _Create create;

  /// Bulk-deletes rows from one of the framework's own tables and returns how
  /// many were removed.
  ///
  /// Unlike [delete], this is awaited end to end: the host runs a single
  /// `DELETE ... WHERE` and reports the row count back, so a caller can tell
  /// "removed nothing" from "never ran". [delete] can do neither — it is
  /// dispatched as a fire-and-forget side effect, which is why every internal
  /// retention cron using it was silently failing.
  ///
  /// Restricted host-side to internal tables and to admin identities; see
  /// [PurgeRecordsRequest] for why skipping the per-row rules walk is sound
  /// there and nowhere else.
  late final _PurgeMany purge;
}

typedef _PurgeMany =
    Future<int> Function({required String tableName, required Where where});

typedef _UpdateMany =
    void Function({
      required String tableName,
      required List<Update> updates,
      required Where where,
      int? limit,
    });

class _Update {
  _Update(this._update);

  final _UpdateMany _update;

  void many({
    required String tableName,
    required List<Update> updates,
    required Where where,
    int? limit,
  }) {
    _update(tableName: tableName, updates: updates, where: where, limit: limit);
  }

  void one({
    required String table,
    required List<Update> updates,
    required Where where,
  }) {
    many(tableName: table, updates: updates, where: where, limit: 1);
  }
}

typedef _DeleteMany =
    void Function({
      required String tableName,
      required Where where,
      int? limit,
    });

class _Delete {
  _Delete(this._delete);

  final _DeleteMany _delete;

  void many({required String tableName, required Where where, int? limit}) {
    _delete(tableName: tableName, where: where, limit: limit);
  }

  void one({required String tableName, required Where where}) {
    many(tableName: tableName, where: where, limit: 1);
  }
}

typedef _CreateMany =
    void Function({
      required String tableName,
      required List<Map<String, dynamic>> objects,
    });

class _Create {
  _Create(this._create);

  final _CreateMany _create;

  void many({
    required String tableName,
    required List<Map<String, dynamic>> objects,
  }) {
    _create(tableName: tableName, objects: objects);
  }

  void one({required String tableName, required Map<String, dynamic> object}) {
    many(tableName: tableName, objects: [object]);
  }
}
