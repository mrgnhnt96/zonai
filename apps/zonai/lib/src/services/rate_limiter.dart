import 'package:clock/clock.dart';
import 'package:raindrop/raindrop.dart' hide Table;
import 'package:resqlite/resqlite.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/internal/tables/rate_limit_table.dart'
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

  /// Fixed policy for external-IdP first-seen provisioning. Not
  /// consumer-overridable through `AuthTableRateLimits` because the
  /// abuse vector this throttle defends against ("compromised IdP
  /// mints unique sub claims to flood the auth table") is the same
  /// shape regardless of consumer schema. Operators tune by tightening
  /// the per-IP slice of the bucket key, not by widening this policy.
  static const _externalIdpProvisioningPolicy = RateLimitPolicy(
    maxRequests: 30,
    window: Duration(hours: 1),
  );

  Future<bool> check({
    required String table,
    required String ipAddress,
    required RateLimitOperation operation,
  }) async {
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

    final policy = response.policy;
    if (policy == null) {
      return true;
    }

    return _checkBucket(
      table: table,
      ipAddress: ipAddress,
      operation: operation,
      policy: policy,
    );
  }

  /// Rate-limits external-IdP first-seen provisioning per
  /// (table, IP, issuer) using the fixed
  /// [_externalIdpProvisioningPolicy]. Separate entry point from
  /// [check] so the consumer policy-override surface
  /// (`AuthTableRateLimits`) is not extended for a framework-level
  /// concern.
  ///
  /// The bucket key in the `_rate_limit` table is composed as
  /// `'<ipAddress>:iss:<issuer>'`, so a compromised issuer cannot
  /// exhaust the budget for sibling issuers behind the same IP, and
  /// a single hostile IP cannot exhaust the budget for legitimate
  /// IPs hitting the same issuer.
  Future<bool> checkExternalIdpProvisioning({
    required String table,
    required String ipAddress,
    required String issuer,
  }) async {
    return _checkBucket(
      table: table,
      ipAddress: '$ipAddress:iss:$issuer',
      operation: RateLimitOperation.externalIdpProvisioning,
      policy: _externalIdpProvisioningPolicy,
    );
  }

  Future<bool> _checkBucket({
    required String table,
    required String ipAddress,
    required RateLimitOperation operation,
    required RateLimitPolicy policy,
  }) async {
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
