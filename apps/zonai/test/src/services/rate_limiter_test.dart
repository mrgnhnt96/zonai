import 'dart:io' as io;

import 'package:clock/clock.dart';
import 'package:file/local.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/services/rate_limit_check.dart';
import 'package:zonai/src/services/rate_limiter.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_response.dart';
import 'package:zonai_schema/src/internal/tables/rate_limit_table.dart'
    as rate_limit_table;
import 'package:zonai_schema/zonai_schema.dart';

import '../../support/temp_directory.dart';

/// The numbers `RateLimiter.check` reports alongside its verdict -- the
/// ones a 429 turns into `Retry-After` and `X-RateLimit-*` (GitHub issue
/// #32). Pinned against a real `_rate_limit` table rather than a mock,
/// because the window arithmetic lives in the same transaction as the
/// counter and the whole point is that the two cannot disagree.
///
/// The window is FIXED: it opens at the first counted request and resets on
/// the first request after `window` has elapsed. A refused request does not
/// count and does not move the window, so every refusal in one window names
/// the same `resetAt`.
void main() {
  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  late io.Directory projectRoot;

  setUp(() async {
    projectRoot = createCanonicalTempSync('zonai_rate_limiter_');
    io.Directory(
      '${projectRoot.path}/.zonai/migrations',
    ).createSync(recursive: true);
    io.File('${projectRoot.path}/zonai.yaml').writeAsStringSync('name: test\n');
  });

  tearDown(() async {
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  const window = Duration(seconds: 60);
  const policy = RateLimitPolicy(maxRequests: 3, window: window);
  const ip = '203.0.113.7';
  final t0 = DateTime.utc(2026, 9, 1, 12, 0, 0);

  /// Runs [body] with a fresh database and a limiter whose policy lookup is
  /// [policies] (table -> per-IP policy; absent means none), recording every
  /// question the limiter asks.
  ///
  /// A create is also offered [counters] (counter name -> column), and
  /// [counter] answers for one of them: the key a value is counted under and
  /// that key's policy, standing in for the worker running the table's
  /// `RateLimitCounter`.
  Future<void> withLimiter(
    Map<String, RateLimitPolicy?> policies,
    Future<void> Function(RateLimiter limiter, List<RateLimitRequest> asked)
    body, {
    Map<String, String> counters = const {},
    (String?, RateLimitPolicy?) Function(String counter, String? value)?
    counter,
  }) async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    final settings = await runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );

    final asked = <RateLimitRequest>[];
    final limiter = RateLimiter(
      resolve: (request) async {
        asked.add(request);
        if (request.counter case final name?) {
          final (key, policy) = counter!(name, request.value);
          return RateLimitResponse(id: request.id, policy: policy, key: key);
        }
        return RateLimitResponse(
          id: request.id,
          policy: policies[request.table],
          counters: request.operation == RateLimitOperation.create
              ? counters
              : const {},
        );
      },
    );

    // `ZonaiDb()` reads settings from the scope, so it is built inside it;
    // the provider then hands the limiter this one instance rather than the
    // module-level singleton `zonaiDbProvider` would otherwise cache.
    ZonaiDb? db;
    await runMergedScopedFuture(
      () async {
        db = ZonaiDb();
        try {
          await runMergedScopedFuture(
            () => body(limiter, asked),
            override: {
              zonaiDbProvider.overrideWith(
                () =>
                    () => db!,
              ),
            },
          );
        } finally {
          await db?.dispose();
        }
      },
      override: {
        fsProvider.overrideWith(LocalFileSystem.new),
        loggerProvider.overrideWith(() => Logger(level: .error)),
        settingsProvider.overrideWith(() => settings),
        processProvider,
        cleanUpProvider,
        executableStopProvider,
        migrateProvider,
      },
    );
  }

  Future<RateLimitCheck> at(
    DateTime now,
    RateLimiter limiter, {
    String table = 'items',
    RateLimitOperation operation = RateLimitOperation.create,
    String? customOperation,
    String ipAddress = ip,
    List<Map<String, dynamic>> rows = const [],
  }) => withClock(
    Clock.fixed(now),
    () => limiter.check(
      table: table,
      ipAddress: ipAddress,
      operation: operation,
      customOperation: customOperation,
      rows: rows,
    ),
  );

  group('a limited bucket', () {
    test('the first request opens a window that resets one window later', () {
      return withLimiter({'items': policy}, (limiter, _) async {
        final check = await at(t0, limiter);

        expect(check.allowed, isTrue);
        expect(check.isUnlimited, isFalse);
        expect(check.limit, 3);
        expect(check.remaining, 2, reason: 'this request is counted');
        expect(check.resetAt, t0.add(window));
        expect(check.table, 'items');
        expect(check.operation, RateLimitOperation.create);
        expect(check.customOperation, isNull);
      });
    });

    test('remaining counts down to 0 and then the bucket refuses', () {
      return withLimiter({'items': policy}, (limiter, _) async {
        expect((await at(t0, limiter)).remaining, 2);
        expect((await at(t0, limiter)).remaining, 1);
        final last = await at(t0, limiter);
        expect(last.allowed, isTrue);
        expect(last.remaining, 0);

        final refused = await at(t0.add(const Duration(seconds: 10)), limiter);
        expect(refused.allowed, isFalse);
        expect(refused.limit, 3);
        expect(refused.remaining, 0);
        expect(refused.resetAt, t0.add(window));
      });
    });

    test('a refused request does not move the window', () {
      // The property the issue's reporter needed: nine clients polling one
      // shared bucket must all be told the same reset instant, or the
      // polling itself keeps the window from ever ending.
      return withLimiter({'items': policy}, (limiter, _) async {
        for (var i = 0; i < 3; i++) {
          await at(t0, limiter);
        }

        final first = await at(t0.add(const Duration(seconds: 5)), limiter);
        final later = await at(t0.add(const Duration(seconds: 59)), limiter);

        expect(first.allowed, isFalse);
        expect(later.allowed, isFalse);
        expect(first.resetAt, t0.add(window));
        expect(
          later.resetAt,
          t0.add(window),
          reason: 'refusals are not counted',
        );

        // And the window really does end when it said it would: one tick
        // before `resetAt` still refuses, `resetAt` itself admits.
        final justBefore = await at(
          t0.add(window - const Duration(milliseconds: 1)),
          limiter,
        );
        expect(justBefore.allowed, isFalse);
      });
    });

    test('the boundary `now - window_start == window` resets the window', () {
      return withLimiter({'items': policy}, (limiter, _) async {
        for (var i = 0; i < 3; i++) {
          await at(t0, limiter);
        }
        expect((await at(t0, limiter)).allowed, isFalse);

        final t1 = t0.add(window);
        final reset = await at(t1, limiter);

        expect(reset.allowed, isTrue);
        expect(reset.remaining, 2, reason: 'count restarted at 1');
        expect(
          reset.resetAt,
          t1.add(window),
          reason: 'the new window starts at the request that reset it',
        );
      });
    });

    test('a custom operation reports the collection, not the storage key', () {
      // Custom ops are stored under `table:op` to reuse the unique index; a
      // client must never see that key, because it is not a collection.
      return withLimiter({'items': policy}, (limiter, asked) async {
        final check = await at(
          t0,
          limiter,
          operation: RateLimitOperation.custom,
          customOperation: 'fill',
        );

        expect(check.table, 'items');
        expect(check.operation, RateLimitOperation.custom);
        expect(check.customOperation, 'fill');
        expect(asked.single.customOperation, 'fill');
      });
    });
  });

  group('an unlimited bucket', () {
    test('always passes and carries no window', () {
      return withLimiter({'items': null}, (limiter, asked) async {
        final check = await at(t0, limiter);

        expect(check.allowed, isTrue);
        expect(check.isUnlimited, isTrue);
        expect(check.limit, isNull);
        expect(check.remaining, isNull);
        expect(check.resetAt, isNull);
        expect(check.table, 'items');
        expect(check.operation, RateLimitOperation.create);

        // Resolved once and remembered; the policy is static for the life
        // of the process.
        await at(t0, limiter);
        await at(t0, limiter);
        expect(asked, hasLength(1));
      });
    });
  });
  group('keyed counters', () {
    const perKey = RateLimitPolicy(maxRequests: 2, window: window);
    const otherIp = '198.51.100.9';

    /// The counter named `app`, keyed on the `api_key` column with the value
    /// itself as the key, and counted at [perKey].
    Future<void> withAppCounter(
      Future<void> Function(RateLimiter limiter, List<RateLimitRequest> asked)
      body, {
      RateLimitPolicy? ipPolicy,
    }) => withLimiter(
      {'items': ipPolicy},
      body,
      counters: {'app': 'api_key'},
      counter: (_, value) => (value, perKey),
    );

    Map<String, dynamic> row(String? apiKey, {String? device}) => {
      'title': 'x',
      'api_key': ?apiKey,
      'install_id': ?device,
    };

    test('a table without counters is still limited per IP only', () {
      return withLimiter({'items': policy}, (limiter, asked) async {
        for (var i = 0; i < 3; i++) {
          await at(t0, limiter, rows: [row('k1')]);
        }
        final refused = await at(t0, limiter, rows: [row('k2')]);

        expect(refused.allowed, isFalse, reason: 'the key plays no part');
        expect(refused.counter, isNull);
        expect(
          await at(t0, limiter, ipAddress: otherIp, rows: [row('k1')]),
          isA<RateLimitCheck>().having((c) => c.allowed, 'allowed', isTrue),
        );
        expect(asked.map((r) => r.counter), everyElement(isNull));
      });
    });

    test('counts per key, so callers on one network do not share it', () {
      return withAppCounter((limiter, _) async {
        expect((await at(t0, limiter, rows: [row('k1')])).allowed, isTrue);
        expect((await at(t0, limiter, rows: [row('k1')])).allowed, isTrue);

        final spent = await at(t0, limiter, rows: [row('k1')]);
        expect(spent.allowed, isFalse);
        expect(spent.counter, 'app');
        expect(spent.limit, 2);

        final other = await at(t0, limiter, rows: [row('k2')]);
        expect(other.allowed, isTrue, reason: 'same IP, different key');
        expect(other.counter, 'app');
        expect(other.remaining, 1);
      });
    });

    test('one key is one counter from every address', () {
      return withAppCounter((limiter, _) async {
        await at(t0, limiter, rows: [row('k1')]);
        await at(t0, limiter, ipAddress: otherIp, rows: [row('k1')]);

        final third = await at(
          t0,
          limiter,
          ipAddress: '192.0.2.44',
          rows: [row('k1')],
        );
        expect(third.allowed, isFalse);
      });
    });

    test('is checked alongside the per-IP counter, and either refuses', () {
      return withAppCounter(ipPolicy: policy, (limiter, _) async {
        final first = await at(t0, limiter, rows: [row('k1')]);
        expect(first.allowed, isTrue);
        expect(first.counter, 'app', reason: 'fewest left: 1 of 2 vs 2 of 3');
        expect(first.remaining, 1);

        await at(t0, limiter, rows: [row('k2')]);
        await at(t0, limiter, rows: [row('k3')]);

        final ipSpent = await at(t0, limiter, rows: [row('k4')]);
        expect(ipSpent.allowed, isFalse, reason: 'three from one address');
        expect(ipSpent.counter, isNull, reason: 'the per-IP counter refused');
      });
    });

    test('a refused create is counted against none of its counters', () {
      return withAppCounter(ipPolicy: policy, (limiter, _) async {
        await at(t0, limiter, rows: [row('k1')]);
        await at(t0, limiter, rows: [row('k1')]);

        // k1 is spent; these are refused and must not use up the per-IP
        // counter, which has one request left.
        for (var i = 0; i < 5; i++) {
          expect((await at(t0, limiter, rows: [row('k1')])).allowed, isFalse);
        }

        final fresh = await at(t0, limiter, rows: [row('k2')]);
        expect(fresh.allowed, isTrue);
        expect(fresh.counter, isNull);
        expect(fresh.remaining, 0);
      });
    });

    test('several counters each get their own key and policy', () {
      const perDevice = RateLimitPolicy(maxRequests: 1, window: window);
      return withLimiter(
        {'items': null},
        counters: {'app': 'api_key', 'device': 'install_id'},
        counter: (name, value) => switch (name) {
          'app' => (value, perKey),
          _ => (value, perDevice),
        },
        (limiter, asked) async {
          final first = await at(t0, limiter, rows: [row('k1', device: 'd1')]);
          expect(first.allowed, isTrue);
          expect(first.counter, 'device');

          final sameDevice = await at(
            t0,
            limiter,
            rows: [row('k1', device: 'd1')],
          );
          expect(sameDevice.allowed, isFalse);
          expect(sameDevice.counter, 'device');

          expect(
            (await at(t0, limiter, rows: [row('k1', device: 'd2')])).allowed,
            isTrue,
          );
          final appSpent = await at(
            t0,
            limiter,
            rows: [row('k1', device: 'd3')],
          );
          expect(appSpent.allowed, isFalse);
          expect(appSpent.counter, 'app');

          final asks = [
            for (final r in asked)
              if (r.counter != null) (r.counter, r.value),
          ];
          expect(asks.take(2), [('app', 'k1'), ('device', 'd1')]);
        },
      );
    });

    test('a refusal reports the spent counter that resets last', () {
      const short = RateLimitPolicy(maxRequests: 1, window: window);
      const long = RateLimitPolicy(maxRequests: 1, window: Duration(hours: 1));
      return withLimiter(
        {'items': null},
        counters: {'app': 'api_key', 'device': 'install_id'},
        counter: (name, value) => (value, name == 'app' ? long : short),
        (limiter, _) async {
          await at(t0, limiter, rows: [row('k1', device: 'd1')]);

          final refused = await at(
            t0,
            limiter,
            rows: [row('k1', device: 'd1')],
          );
          expect(refused.allowed, isFalse);
          expect(refused.counter, 'app');
          expect(refused.resetAt, t0.add(const Duration(hours: 1)));
        },
      );
    });

    test('a row without the value is counted on its IP, apart from the '
        'per-IP counter', () {
      final policiesAskedFor = <String?>[];
      return withLimiter(
        {'items': policy},
        counters: {'app': 'api_key'},
        counter: (_, value) {
          policiesAskedFor.add(value);
          return (value, perKey);
        },
        (limiter, _) async {
          for (final rows in [
            [row(null)],
            [
              <String, dynamic>{'api_key': ''},
            ],
            [
              <String, dynamic>{'api_key': true},
            ],
            [row('k1'), row('k2')],
          ]) {
            policiesAskedFor.clear();
            await at(t0, limiter, rows: rows);
            expect(policiesAskedFor, [null], reason: '$rows');
          }

          // In a fresh window, two keyless creates spend the keyless bucket
          // for this address while the per-IP counter still has room.
          final t1 = t0.add(const Duration(hours: 1));
          await at(t1, limiter, rows: [row(null)]);
          await at(t1, limiter, rows: [row(null)]);
          final spent = await at(t1, limiter, rows: [row(null)]);
          expect(spent.allowed, isFalse);
          expect(spent.counter, 'app');

          expect(
            (await at(
              t1,
              limiter,
              ipAddress: otherIp,
              rows: [row(null)],
            )).allowed,
            isTrue,
            reason: 'keyless creates are counted per address',
          );
        },
      );
    });

    test('rows of one createMany that agree on the value share its key', () {
      return withAppCounter((limiter, asked) async {
        await at(t0, limiter, rows: [row('k1'), row('k1')]);
        expect(asked.last.value, 'k1');
      });
    });

    test('a value the table does not recognise is counted on the IP', () {
      return withLimiter(
        {'items': null},
        counters: {'app': 'api_key'},
        // The worker's `key` turned every value down.
        counter: (_, value) => (null, perKey),
        (limiter, _) async {
          await at(t0, limiter, rows: [row('made-up-1')]);
          await at(t0, limiter, rows: [row('made-up-2')]);

          final rotated = await at(t0, limiter, rows: [row('made-up-3')]);
          expect(
            rotated.allowed,
            isFalse,
            reason: 'rotating unrecognised keys lands on one counter',
          );
        },
      );
    });

    test('stores a hash of the key, never the key itself', () {
      return withAppCounter((limiter, _) async {
        await at(t0, limiter, rows: [row('secret-api-key')]);
        await at(t0, limiter, rows: [row(null)]);

        final db = await zonaiDB.open();
        final stored = await db.select().from(rate_limit_table.rateLimits);
        final byClient = {for (final e in stored) e.clientIp: e.table};

        expect(byClient.keys, hasLength(2));
        expect(byClient.values, everyElement('items#app'));
        expect(byClient.keys, contains(ip));
        final hashed = byClient.keys.firstWhere((k) => k != ip);
        expect(hashed, matches(RegExp(r'^key:[0-9a-f]{64}$')));
        expect(hashed, isNot(contains('secret-api-key')));
      });
    });

    test('a counter whose policy is null is left out', () {
      return withLimiter(
        {'items': policy},
        counters: {'app': 'api_key'},
        counter: (_, value) => (value, value == 'vip' ? null : perKey),
        (limiter, _) async {
          final vip = await at(t0, limiter, rows: [row('vip')]);
          expect(vip.counter, isNull, reason: 'only the per-IP counter');
          expect(vip.remaining, 2);
        },
      );
    });

    test('with no per-IP policy and every counter unlimited, a create is '
        'unlimited', () {
      return withLimiter(
        {'items': null},
        counters: {'app': 'api_key'},
        counter: (_, value) => (value, null),
        (limiter, _) async {
          final check = await at(t0, limiter, rows: [row('k1')]);
          expect(check.allowed, isTrue);
          expect(check.isUnlimited, isTrue);
        },
      );
    });

    test('the counters are looked up once, their keys on every create', () {
      return withAppCounter((limiter, asked) async {
        await at(t0, limiter, rows: [row('k1')]);
        await at(t0, limiter, rows: [row('k1')]);

        expect(asked.where((r) => r.counter == null), hasLength(1));
        expect(asked.where((r) => r.counter == 'app'), hasLength(2));
      });
    });

    test('other operations are not keyed', () {
      return withAppCounter(ipPolicy: policy, (limiter, asked) async {
        final check = await at(
          t0,
          limiter,
          operation: RateLimitOperation.update,
          rows: [row('k1')],
        );
        expect(check.counter, isNull);
        expect(asked.where((r) => r.counter != null), isEmpty);
      });
    });
  });

  group('session handoff limits', () {
    const handoff = RateLimitPolicy.sessionHandoff;

    for (final operation in const [
      RateLimitOperation.handoffCreate,
      RateLimitOperation.handoffExchange,
    ]) {
      Future<RateLimitCheck> hit(
        RateLimiter limiter, {
        DateTime? now,
        String ipAddress = ip,
      }) => at(
        now ?? t0,
        limiter,
        table: 'users',
        operation: operation,
        ipAddress: ipAddress,
      );

      test('${operation.name} trips after the policy allows its last '
          'request from one IP', () {
        return withLimiter({'users': handoff}, (limiter, _) async {
          for (var i = 0; i < handoff.maxRequests; i++) {
            expect((await hit(limiter)).allowed, isTrue, reason: 'request $i');
          }

          expect((await hit(limiter)).allowed, isFalse);
        });
      });

      test('${operation.name} counts each IP on its own', () {
        return withLimiter({'users': handoff}, (limiter, _) async {
          for (var i = 0; i < handoff.maxRequests; i++) {
            await hit(limiter);
          }
          expect((await hit(limiter)).allowed, isFalse);

          expect(
            (await hit(limiter, ipAddress: '198.51.100.9')).allowed,
            isTrue,
          );
        });
      });

      test('${operation.name} opens again once the window passes', () {
        return withLimiter({'users': handoff}, (limiter, _) async {
          for (var i = 0; i < handoff.maxRequests; i++) {
            await hit(limiter);
          }
          expect((await hit(limiter)).allowed, isFalse);

          final later = t0.add(handoff.window);
          expect((await hit(limiter, now: later)).allowed, isTrue);
        });
      });
    }

    test('creating and exchanging codes count separately', () {
      return withLimiter({'users': handoff}, (limiter, _) async {
        for (var i = 0; i < handoff.maxRequests; i++) {
          await at(
            t0,
            limiter,
            table: 'users',
            operation: RateLimitOperation.handoffCreate,
          );
        }

        final exchange = await at(
          t0,
          limiter,
          table: 'users',
          operation: RateLimitOperation.handoffExchange,
        );
        expect(exchange.allowed, isTrue);
      });
    });
  });
}
