import 'package:clock/clock.dart';
import 'package:raindrop/raindrop.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';
import 'package:zonai/src/internal/rate_limit_collection.dart'
    as rate_limit_table;
import 'package:zonai_schema/zonai_schema.dart';

// TODO: we need a cron to clean this every day or something
final class RateLimiter {
  RateLimiter();

  Mailman<RateLimitRequest, RateLimitResponse>? __mailman;
  Mailman<RateLimitRequest, RateLimitResponse> get _mailman =>
      __mailman ??= Mailman(
        debugName: 'RATE_LIMIT',
        executablePath: settings.compiledRateLimitPath,
        fromJson: RateLimitResponse.fromJson,
      );

  Future<bool> check({
    required String collection,
    required String ipAddress,
    required RateLimitOperation operation,
  }) async {
    final response = await _mailman
        .send<RateLimitResponse>(
          RateLimitRequest(collection: collection, operation: operation),
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

    final policy = response.policy;
    if (policy == null) {
      return true;
    }

    final db = await zonaiDB.open();
    final now = clock.now();
    final table = rate_limit_table.rateLimits;

    final rows = await db
        .select()
        .from(table)
        .where(
          table.collection.equals(collection) &
              table.clientIp.equals(ipAddress) &
              table.operation.equals(operation),
        )
        .limit(1);

    final entry = rows.singleOrNull;

    if (entry == null) {
      await db.insert(into: table).values([
        rate_limit_table.RateLimitEntry(
          clientIp: ipAddress,
          collection: collection,
          operation: operation,
          windowStart: now,
        ),
      ]);

      return true;
    }

    if (now.difference(entry.windowStart) >= policy.window) {
      await db
          .update(table)
          .set(table.windowStart.to(now), table.count.to(1))
          .where(table.id.equals(entry.id));
      return true;
    }

    if (entry.count >= policy.maxRequests) {
      return false;
    }

    await db
        .update(table)
        .set(table.count.to(entry.count + 1))
        .where(table.id.equals(entry.id));

    return true;
  }
}
