part of '../message_handler.dart';

final _mutateProvider = create<_Mutate>(_Mutate._);
_Mutate get mutate => read(_mutateProvider);

class _Mutate {
  _Mutate({
    required _UpdateMany update,
    required _DeleteMany delete,
    required _CreateMany create,
  }) {
    this.update = _Update(update);
    this.delete = _Delete(delete);
    this.create = _Create(create);
  }
  _Mutate._() {
    update = _Update(
      ({required collection, required updates, required where, limit}) {},
    );
    delete = _Delete(
      ({required collection, required updates, required where, limit}) {},
    );
    create = _Create(({required collection, required objects}) {});
  }

  late final _Update update;
  late final _Delete delete;
  late final _Create create;
}

typedef _UpdateMany =
    void Function({
      required String collection,
      required List<Update> updates,
      required Where where,
      int? limit,
    });

class _Update {
  _Update(this._update);

  final _UpdateMany _update;

  void many({
    required String collection,
    required List<Update> updates,
    required Where where,
    int? limit,
  }) {
    _update(
      collection: collection,
      updates: updates,
      where: where,
      limit: limit,
    );
  }

  void one({
    required String collection,
    required List<Update> updates,
    required Where where,
  }) {
    many(collection: collection, updates: updates, where: where, limit: 1);
  }
}

typedef _DeleteMany =
    void Function({
      required String collection,
      required List<Update> updates,
      required Where where,
      int? limit,
    });

class _Delete {
  _Delete(this._delete);

  final _DeleteMany _delete;

  void many({
    required String collection,
    required List<Update> updates,
    required Where where,
    int? limit,
  }) {
    _delete(
      collection: collection,
      updates: updates,
      where: where,
      limit: limit,
    );
  }

  void one({
    required String collection,
    required List<Update> updates,
    required Where where,
  }) {
    many(collection: collection, updates: updates, where: where, limit: 1);
  }
}

typedef _CreateMany =
    void Function({
      required String collection,
      required List<Map<String, dynamic>> objects,
    });

class _Create {
  _Create(this._create);

  final _CreateMany _create;

  void many({
    required String collection,
    required List<Map<String, dynamic>> objects,
  }) {
    _create(collection: collection, objects: objects);
  }

  void one({required String collection, required Map<String, dynamic> object}) {
    many(collection: collection, objects: [object]);
  }
}
