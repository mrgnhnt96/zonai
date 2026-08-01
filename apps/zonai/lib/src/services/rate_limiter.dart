import 'package:clock/clock.dart';
import 'package:raindrop/raindrop.dart' hide Table;
import 'package:resqlite/resqlite.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/internal/tables/rate_limit_table.dart'
    as rate_limit_table;
import 'package:zonai/src/messengers/rate_limit_mailman.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

// TODO: we need a cron to clean this every day or something
final class RateLimiter {
  RateLimiter();

  RateLimitsMailman? __mailman;
  RateLimitsMailman get _mailman => __mailman ??= RateLimitsMailman();

  /// Tables whose rate-limit worker returned `null` (unlimited). After the
  /// first resolve we skip the IPC hop entirely — the policy is static for
  /// the life of the process (worker recompile restarts the server).
  final Set<(String, RateLimitOperation)> _unlimited = {};

  /// Non-null policies resolved from the worker, keyed by table+operation.
  final Map<(String, RateLimitOperation), RateLimitPolicy> _policies = {};

  Future<bool> check({
    required String table,
    required String ipAddress,
    required RateLimitOperation operation,
  }) async {
    final key = (table, operation);
    if (_unlimited.contains(key)) {
      return true;
    }

    var policy = _policies[key];
    if (policy == null && !_policies.containsKey(key)) {
      final response = await _mailman
          .send<RateLimitResponse>(
            RateLimitRequest(table: table, operation: operation),
          )
          .catchError((e, stack) {
            if (e is ExecutableUnavailableException) {
              return RateLimitResponse(
                policy: RateLimitPolicy.defaultPolicy,
                id: '',
              );
            }

            throw Error.throwWithStackTrace(e, stack);
          });

      final resolved = response.policy;
      if (resolved == null) {
        _unlimited.add(key);
        return true;
      }
      _policies[key] = resolved;
      policy = resolved;
    }

    if (policy == null) {
      return true;
    }

    final db = await zonaiDB.open();
    final now = clock.now();
    final rateLimitSchema = rate_limit_table.rateLimits;

    // Concurrent requests can both miss an existing row (reads use a separate
    // sqlite connection from writes) and race on INSERT. Retry once when the
    // unique bucket index rejects a duplicate insert.
    for (var attempt = 0; attempt < 2; attempt++) {
      final rows = await db
          .select()
          .from(rateLimitSchema)
          .where(
            rateLimitSchema.table.equals(table) &
                rateLimitSchema.clientIp.equals(ipAddress) &
                rateLimitSchema.operation.equals(operation),
          )
          .limit(1);

      final entry = rows.singleOrNull;

      if (entry == null) {
        try {
          await db.insert(into: rateLimitSchema).values([
            rate_limit_table.RateLimitEntry(
              clientIp: ipAddress,
              table: table,
              operation: operation,
              windowStart: now,
            ),
          ]);

          return true;
        } on ResqliteQueryException catch (e) {
          if (e.sqliteCode == 19 && attempt == 0) continue;
          rethrow;
        }
      }

      if (now.difference(entry.windowStart) >= policy.window) {
        await db
            .update(rateLimitSchema)
            .set(
              rateLimitSchema.windowStart.to(now),
              rateLimitSchema.count.to(1),
            )
            .where(rateLimitSchema.id.equals(entry.id));
        return true;
      }

      if (entry.count >= policy.maxRequests) {
        return false;
      }

      await db
          .update(rateLimitSchema)
          .set(rateLimitSchema.count.to(entry.count + 1))
          .where(rateLimitSchema.id.equals(entry.id));

      return true;
    }

    throw StateError('Rate limit check failed after insert conflict retry');
  }
}
