import 'package:clock/clock.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/internal/tables/rate_limit_table.dart'
    as rate_limit_table;
import 'package:zonai/src/messengers/rate_limit_mailman.dart';
import 'package:zonai/src/services/rate_limit_check.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class RateLimiter {
  /// [resolvePolicy] answers which policy governs a bucket; `null` means
  /// unlimited. Defaults to asking the compiled rate-limit worker. Tests
  /// inject a lookup so the window arithmetic can be pinned without a
  /// worker executable on disk.
  RateLimiter({
    Future<RateLimitPolicy?> Function(RateLimitRequest)? resolvePolicy,
  }) : _resolvePolicy = resolvePolicy;

  final Future<RateLimitPolicy?> Function(RateLimitRequest)? _resolvePolicy;

  RateLimitsMailman? __mailman;
  RateLimitsMailman get _mailman => __mailman ??= RateLimitsMailman();

  Future<RateLimitPolicy?> _resolveThroughWorker(
    RateLimitRequest request,
  ) async {
    final response = await _mailman.send<RateLimitResponse>(request).catchError(
      (e, stack) {
        if (e is ExecutableUnavailableException) {
          return RateLimitResponse(
            policy: RateLimitPolicy.defaultPolicy,
            id: '',
          );
        }

        throw Error.throwWithStackTrace(e, stack);
      },
    );
    return response.policy;
  }

  /// Tables whose rate-limit worker returned `null` (unlimited). After the
  /// first resolve we skip the IPC hop entirely — the policy is static for
  /// the life of the process (worker recompile restarts the server).
  final Set<(String, RateLimitOperation, String?)> _unlimited = {};

  /// Non-null policies resolved from the worker, keyed by
  /// table+operation+custom operation name (`null` for every non-custom op).
  final Map<(String, RateLimitOperation, String?), RateLimitPolicy> _policies =
      {};

  /// Whether [operationName] is a registered custom operation
  /// (`TableRules.customOperations`) for [table] — checked before the name
  /// is ever used as a rate-limit bucket dimension, so a caller can't rotate
  /// an unregistered name to dodge a limit (each new name would otherwise
  /// start at a fresh counter).
  ///
  /// Returns `null` when this can't be answered cheaply (rules aren't linked
  /// in-process — e.g. `ZONAI_FORCE_WORKERS=1`). Callers should treat `null`
  /// as "can't validate" and fall back to the coarse per-table `.custom`
  /// bucket rather than trust an unvalidated name; the rules layer still
  /// denies an unregistered operation regardless, so this only protects the
  /// rate limiter itself from the bypass, not authorization.
  bool? isRegisteredCustomOperation({
    required String table,
    required String operationName,
  }) {
    if (!HostWorkerRegistries.useInProcessRules) {
      return null;
    }
    return HostWorkerRegistries.rules!
        .customTableOperationNames(table)
        .contains(operationName);
  }

  /// Counts one request from [ipAddress] against the bucket for [table] +
  /// [operation] (+ [customOperation]) and reports the verdict together with
  /// the window it was decided in -- see [RateLimitCheck] for what a caller
  /// can put in a 429 from it.
  Future<RateLimitCheck> check({
    required String table,
    required String ipAddress,
    required RateLimitOperation operation,
    String? customOperation,
  }) async {
    final key = (table, operation, customOperation);
    RateLimitCheck unlimited() => RateLimitCheck.unlimited(
      table: table,
      operation: operation,
      customOperation: customOperation,
    );

    if (_unlimited.contains(key)) {
      return unlimited();
    }

    var policy = _policies[key];
    if (policy == null && !_policies.containsKey(key)) {
      final resolved = await (_resolvePolicy ?? _resolveThroughWorker)(
        RateLimitRequest(
          table: table,
          operation: operation,
          customOperation: customOperation,
        ),
      );

      if (resolved == null) {
        _unlimited.add(key);
        return unlimited();
      }
      _policies[key] = resolved;
      policy = resolved;
    }

    if (policy == null) {
      return unlimited();
    }
    // Captured by the transaction closure below; a non-final local loses its
    // null-promotion once captured, even though it is never reassigned again.
    final resolvedPolicy = policy;

    final db = await zonaiDB.open();
    final now = clock.now();
    final rateLimitSchema = rate_limit_table.rateLimits;

    // Custom operations bucket per operation name, not just per table: reuse
    // the existing (clientIp, table, operation) unique index by folding the
    // name into the free-text `table` column instead of the closed
    // `operation` enum column, so `fill` and `reserve` on the same table get
    // independent counters with no schema migration.
    assert(
      !table.contains(':'),
      'Table name "$table" contains ":", which collides with the '
      '"table:operation" custom-op rate-limit bucket key format below.',
    );
    final bucketTable = customOperation == null
        ? table
        : '$table:$customOperation';

    // The read-then-write below must be atomic: concurrent requests for the
    // same bucket can both miss the row on a plain `db.select` (reads use a
    // separate sqlite connection from writes) and then race each other's
    // INSERT. A single retry survived one collision but rethrew the second
    // one -- surfacing as an uncaught 500 rather than a 429 -- once enough
    // requests raced the same bucket at once. `db.transaction` runs the whole
    // select-then-insert-or-update through resqlite's writer: Database
    // .transaction is `writer.locked(() => writer.transaction(body))`
    // (libs/resqlite/lib/src/database.dart:455), so the FIFO writer mutex
    // spans the entire BEGIN IMMEDIATE -> body -> COMMIT rather than each
    // statement. The row this transaction reads is guaranteed to still be the
    // row (or absence of one) it acts on.
    //
    // THE SCOPE OF THAT GUARANTEE, because it is narrower than it looks and
    // the difference is a future 500. The mutex belongs to one `Writer`, which
    // belongs to one `ZonaiDb`, which is held in a TOP-LEVEL static -- and
    // top-level statics in Dart are per-ISOLATE, not per-process (see
    // `_db` in lib/src/deps/zonai_db.dart). So this serialises every
    // `check()` that shares one isolate's `ZonaiDb`, which today is all of
    // them: the only `Isolate.spawn*` in this package is mailman.dart's, and
    // it spawns db WORKERS (ops/rules), never a second request handler. This
    // code path runs on the main isolate and opens the database directly.
    // Give the server a second isolate for throughput, or let a worker open
    // its own ZonaiDb and touch _rate_limit, and there are two writers with
    // two mutexes contending at the SQLite level -- where BEGIN IMMEDIATE
    // yields SQLITE_BUSY rather than queueing, and the 500 comes back wearing
    // a different hat. A retry loop would not save it either; the fix then is
    // one writer, or an atomic upsert.
    RateLimitCheck verdict({
      required bool allowed,
      required int count,
      required DateTime windowStart,
    }) => RateLimitCheck(
      allowed: allowed,
      table: table,
      operation: operation,
      customOperation: customOperation,
      limit: resolvedPolicy.maxRequests,
      remaining: (resolvedPolicy.maxRequests - count).clamp(
        0,
        resolvedPolicy.maxRequests,
      ),
      // Fixed window: it resets `window` after the request that opened it,
      // whatever happens in between. UTC so the instant compares and
      // serialises the same way whether it came from `clock.now()` or from
      // a row SQLite handed back in local time.
      resetAt: windowStart.add(resolvedPolicy.window).toUtc(),
    );

    return db.transaction((tx) async {
      final rows = await tx
          .select()
          .from(rateLimitSchema)
          .where(
            rateLimitSchema.table.equals(bucketTable) &
                rateLimitSchema.clientIp.equals(ipAddress) &
                rateLimitSchema.operation.equals(operation),
          )
          .limit(1);

      final entry = rows.singleOrNull;

      if (entry == null) {
        await tx.insert(into: rateLimitSchema).values([
          rate_limit_table.RateLimitEntry(
            clientIp: ipAddress,
            table: bucketTable,
            operation: operation,
            windowStart: now,
          ),
        ]);
        return verdict(allowed: true, count: 1, windowStart: now);
      }

      if (now.difference(entry.windowStart) >= resolvedPolicy.window) {
        await tx
            .update(rateLimitSchema)
            .set(
              rateLimitSchema.windowStart.to(now),
              rateLimitSchema.count.to(1),
            )
            .where(rateLimitSchema.id.equals(entry.id));
        return verdict(allowed: true, count: 1, windowStart: now);
      }

      if (entry.count >= resolvedPolicy.maxRequests) {
        // Refused requests are not counted and do not move the window, so
        // `resetAt` is the same instant every refusal in this window reports.
        return verdict(
          allowed: false,
          count: entry.count,
          windowStart: entry.windowStart,
        );
      }

      await tx
          .update(rateLimitSchema)
          .set(rateLimitSchema.count.to(entry.count + 1))
          .where(rateLimitSchema.id.equals(entry.id));

      return verdict(
        allowed: true,
        count: entry.count + 1,
        windowStart: entry.windowStart,
      );
    });
  }
}
