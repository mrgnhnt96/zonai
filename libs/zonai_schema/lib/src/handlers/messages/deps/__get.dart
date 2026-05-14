part of '../message_handler.dart';

typedef _GetManyRecords =
    Future<List<Map<String, Object?>>?> Function({
      required String collection,
      required Where where,
      int? limit,
      int? offset,
      Jwt? jwt,
    });

typedef _GetOneRecord =
    Future<Map<String, Object?>?> Function({
      required String collection,
      required Where where,
      int? offset,
      Jwt? jwt,
    });

final _getRecordRequestProvider = create<_GetRecords>(_GetRecords._);

_GetRecords get get => read(_getRecordRequestProvider);

class _GetRecords {
  _GetRecords._() {
    many = ({required collection, required where, limit, offset, jwt}) async =>
        null;
    one = ({required collection, required where, offset, jwt}) async => null;
  }

  _GetRecords(this.many) {
    one = ({required collection, required where, offset, jwt}) async {
      final result = await many(
        collection: collection,
        where: where,
        limit: 1,
        offset: offset,
      );

      return result?.single;
    };
  }

  late final _GetManyRecords many;
  late final _GetOneRecord one;
}
