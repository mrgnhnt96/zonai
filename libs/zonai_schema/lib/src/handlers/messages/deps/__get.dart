part of '../message_handler.dart';

typedef _GetManyRecords =
    Future<List<Map<String, Object?>>?> Function({
      required String tableName,
      required Where where,
      int? limit,
      int? offset,
      Jwt? jwt,
    });

typedef _GetOneRecord =
    Future<Map<String, Object?>?> Function({
      required String tableName,
      required Where where,
      int? offset,
      Jwt? jwt,
    });

final _getRecordRequestProvider = create<_Get>(_Get._);

_Get get get => read(_getRecordRequestProvider);

class _Get {
  _Get._() {
    many =
        ({
          required String tableName,
          required where,
          limit,
          offset,
          jwt,
        }) async => null;
    one = ({required String tableName, required where, offset, jwt}) async =>
        null;
  }

  _Get(this.many) {
    one = ({required String tableName, required where, offset, jwt}) async {
      final result = await many(
        tableName: tableName,
        where: where,
        limit: 1,
        offset: offset,
        jwt: jwt,
      );

      return result?.single;
    };
  }

  late final _GetManyRecords many;
  late final _GetOneRecord one;
}
