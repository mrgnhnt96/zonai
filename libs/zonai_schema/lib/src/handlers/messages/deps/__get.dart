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

/// The JWT of the request whose scope [get] is being called from.
///
/// `mutate` and `email` are built *per request*, inside
/// `MessageHandler.runWithParent`, so they close over `request.jwt` directly
/// and every call already acts as the request's identity. `get` cannot do
/// that: it is bound once for the whole listen loop, before any request
/// exists. This ref carries the identity across that gap so both halves of the
/// API default the same way.
///
/// Without it the two halves disagree, and a cron is where that bites: a job
/// that *writes* runs as [CronJwt] and succeeds, while a job that *reads* is
/// anonymous and is denied by any rule requiring an identity — the least
/// guessable combination available, and the opposite of what `docs/cron.md`
/// describes. See `test/src/handlers/cron/cron_get_jwt_test.dart`.
///
/// An explicit `jwt:` argument still wins, so a caller that deliberately reads
/// as someone else — or as nobody — keeps that ability. This only supplies a
/// default where there was none.
final _ambientJwtProvider = create<Jwt?>(() => null);

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
