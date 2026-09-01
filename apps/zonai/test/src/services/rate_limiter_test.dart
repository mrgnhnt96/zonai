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
  /// [policies] (table -> policy; absent means unlimited), counting how many
  /// times the lookup is consulted.
  Future<void> withLimiter(
    Map<String, RateLimitPolicy?> policies,
    Future<void> Function(RateLimiter limiter, List<RateLimitRequest> asked)
    body,
  ) async {
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
      resolvePolicy: (request) async {
        asked.add(request);
        return policies[request.table];
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
  }) => withClock(
    Clock.fixed(now),
    () => limiter.check(
      table: table,
      ipAddress: ip,
      operation: operation,
      customOperation: customOperation,
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
}
