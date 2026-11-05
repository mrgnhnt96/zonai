import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
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
  /// [resolve] answers the rate-limit worker's questions: which policy
  /// governs a bucket (`null` means unlimited), which keyed counters a create
  /// has, and which key and policy one of those counters gives a value.
  /// Defaults to asking the compiled rate-limit worker. Tests inject a lookup
  /// so the window arithmetic can be pinned without a worker executable on
  /// disk.
  RateLimiter({Future<RateLimitResponse> Function(RateLimitRequest)? resolve})
    : _resolve = resolve;

  final Future<RateLimitResponse> Function(RateLimitRequest)? _resolve;

  RateLimitsMailman? __mailman;
  RateLimitsMailman get _mailman => __mailman ??= RateLimitsMailman();

  Future<RateLimitResponse> _resolveThroughWorker(RateLimitRequest request) {
    return _mailman.send<RateLimitResponse>(request).catchError((e, stack) {
      if (e is ExecutableUnavailableException) {
        return RateLimitResponse(policy: RateLimitPolicy.defaultPolicy, id: '');
      }

      throw Error.throwWithStackTrace(e, stack);
    });
  }

  Future<RateLimitResponse> _ask(RateLimitRequest request) =>
      (_resolve ?? _resolveThroughWorker)(request);

  /// What the worker said about each table+operation+custom operation name
  /// (`null` for every non-custom op): the per-IP policy and the keyed
  /// counters. Both are static for the life of the process (a worker
  /// recompile restarts the server), so after the first resolve the IPC hop
  /// is skipped. A keyed counter's key and policy are not cached here: they
  /// depend on the submitted value.
  final Map<(String, RateLimitOperation, String?), _Plan> _plans = {};

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
  ///
  /// For a create, [rows] are the submitted rows. A table's keyed counters
  /// (`TableRateLimits.createCounters`) read their key from them, and the
  /// request is counted against each of those counters as well as the per-IP
  /// one. It is refused when any one of them is spent, and then counted
  /// against none of them.
  Future<RateLimitCheck> check({
    required String table,
    required String ipAddress,
    required RateLimitOperation operation,
    String? customOperation,
    List<Map<String, dynamic>> rows = const [],
  }) async {
    RateLimitCheck unlimited() => RateLimitCheck.unlimited(
      table: table,
      operation: operation,
      customOperation: customOperation,
    );

    final planKey = (table, operation, customOperation);
    final plan = _plans[planKey] ??= _Plan.from(
      await _ask(
        RateLimitRequest(
          table: table,
          operation: operation,
          customOperation: customOperation,
        ),
      ),
    );

    if (plan.isUnlimited) {
      return unlimited();
    }

    // Custom operations bucket per operation name, not just per table: reuse
    // the existing (clientIp, table, operation) unique index by folding the
    // name into the free-text `table` column instead of the closed
    // `operation` enum column, so `fill` and `reserve` on the same table get
    // independent counters with no schema migration. Keyed counters fold the
    // same way, as `table#counter`, with their key in the `client_ip` column.
    assert(
      !table.contains(':') && !table.contains('#'),
      'Table name "$table" contains ":" or "#", which collides with the '
      '"table:operation" and "table#counter" rate-limit bucket key formats '
      'below.',
    );

    final buckets = [
      if (plan.policy case final policy?)
        _Bucket(
          table: customOperation == null ? table : '$table:$customOperation',
          client: ipAddress,
          policy: policy,
        ),
      for (final MapEntry(key: name, value: column) in plan.counters.entries)
        ?await _counterBucket(
          table: table,
          operation: operation,
          ipAddress: ipAddress,
          name: name,
          value: _sharedValue(rows, column),
        ),
    ];

    if (buckets.isEmpty) {
      return unlimited();
    }

    final db = await zonaiDB.open();
    final now = clock.now();
    final rateLimitSchema = rate_limit_table.rateLimits;

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
    // statement. The rows this transaction reads are guaranteed to still be
    // the rows (or absence of them) it acts on, which is also what lets a
    // request with several counters be refused or counted on all of them
    // at once.
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
    RateLimitCheck verdict(
      _Bucket bucket, {
      required bool allowed,
      required int count,
      required DateTime windowStart,
    }) => RateLimitCheck(
      allowed: allowed,
      table: table,
      operation: operation,
      customOperation: customOperation,
      counter: bucket.counter,
      limit: bucket.policy.maxRequests,
      remaining: (bucket.policy.maxRequests - count).clamp(
        0,
        bucket.policy.maxRequests,
      ),
      // Fixed window: it resets `window` after the request that opened it,
      // whatever happens in between. UTC so the instant compares and
      // serialises the same way whether it came from `clock.now()` or from
      // a row SQLite handed back in local time.
      resetAt: windowStart.add(bucket.policy.window).toUtc(),
    );

    return db.transaction((tx) async {
      final steps = <(RateLimitCheck, Future<void> Function())>[];

      for (final bucket in buckets) {
        final found = await tx
            .select()
            .from(rateLimitSchema)
            .where(
              rateLimitSchema.table.equals(bucket.table) &
                  rateLimitSchema.clientIp.equals(bucket.client) &
                  rateLimitSchema.operation.equals(operation),
            )
            .limit(1);

        final entry = found.singleOrNull;

        if (entry == null) {
          steps.add((
            verdict(bucket, allowed: true, count: 1, windowStart: now),
            () => tx.insert(into: rateLimitSchema).values([
              rate_limit_table.RateLimitEntry(
                clientIp: bucket.client,
                table: bucket.table,
                operation: operation,
                windowStart: now,
              ),
            ]),
          ));
          continue;
        }

        if (now.difference(entry.windowStart) >= bucket.policy.window) {
          steps.add((
            verdict(bucket, allowed: true, count: 1, windowStart: now),
            () => tx
                .update(rateLimitSchema)
                .set(
                  rateLimitSchema.windowStart.to(now),
                  rateLimitSchema.count.to(1),
                )
                .where(rateLimitSchema.id.equals(entry.id)),
          ));
          continue;
        }

        if (entry.count >= bucket.policy.maxRequests) {
          // Refused requests are not counted and do not move the window, so
          // `resetAt` is the same instant every refusal in this window
          // reports.
          steps.add((
            verdict(
              bucket,
              allowed: false,
              count: entry.count,
              windowStart: entry.windowStart,
            ),
            () async {},
          ));
          continue;
        }

        steps.add((
          verdict(
            bucket,
            allowed: true,
            count: entry.count + 1,
            windowStart: entry.windowStart,
          ),
          () => tx
              .update(rateLimitSchema)
              .set(rateLimitSchema.count.to(entry.count + 1))
              .where(rateLimitSchema.id.equals(entry.id)),
        ));
      }

      final refusals = [
        for (final (check, _) in steps)
          if (!check.allowed) check,
      ];
      if (refusals.isNotEmpty) {
        // Counted against none of them. The request passes again only once
        // every spent counter has reset, so report the one that resets last.
        return refusals.reduce(
          (a, b) => b.resetAt!.isAfter(a.resetAt!) ? b : a,
        );
      }

      for (final (_, write) in steps) {
        await write();
      }

      // The counter that is closest to refusing is the one worth reporting.
      return [
        for (final (check, _) in steps) check,
      ].reduce((a, b) => b.remaining! < a.remaining! ? b : a);
    });
  }

  Future<_Bucket?> _counterBucket({
    required String table,
    required RateLimitOperation operation,
    required String ipAddress,
    required String name,
    required String? value,
  }) async {
    final response = await _ask(
      RateLimitRequest(
        table: table,
        operation: operation,
        counter: name,
        value: value,
      ),
    );

    final policy = response.policy;
    if (policy == null) {
      return null;
    }

    return _Bucket(
      table: '$table#$name',
      client: switch (response.key) {
        // Hashed so the table never holds a raw API key or other secret the
        // counter is keyed on; prefixed so a key can never land in the same
        // bucket as an IP address.
        final key? => 'key:${sha256.convert(utf8.encode(key))}',
        null => ipAddress,
      },
      policy: policy,
      counter: name,
    );
  }

  /// The value every row has in [column], as a string, or `null` when a row
  /// has none, an empty one, one that is not a string or number, or a
  /// different one from another row -- so a `createMany` can't spread its
  /// rows over several keys.
  static String? _sharedValue(List<Map<String, dynamic>> rows, String column) {
    String? shared;
    for (final row in rows) {
      final value = switch (row[column]) {
        final String value when value.isNotEmpty => value,
        final num value => '$value',
        _ => null,
      };
      if (value == null || (shared != null && value != shared)) {
        return null;
      }
      shared = value;
    }
    return shared;
  }
}

final class _Plan {
  _Plan.from(RateLimitResponse response)
    : policy = response.policy,
      counters = response.counters;

  /// The per-IP counter's policy, or `null` when there is none.
  final RateLimitPolicy? policy;

  /// Keyed counter name to the column whose value keys it.
  final Map<String, String> counters;

  bool get isUnlimited => policy == null && counters.isEmpty;
}

final class _Bucket {
  const _Bucket({
    required this.table,
    required this.client,
    required this.policy,
    this.counter,
  });

  /// The `table` column of the bucket's row.
  final String table;

  /// The `client_ip` column of the bucket's row: the caller's IP address, or
  /// `key:` and the hash of a keyed counter's key.
  final String client;

  final RateLimitPolicy policy;

  /// The keyed counter's name, `null` for the per-IP counter.
  final String? counter;
}
