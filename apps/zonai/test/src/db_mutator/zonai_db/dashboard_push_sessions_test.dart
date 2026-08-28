import 'dart:async';
import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';

import '../../../support/temp_directory.dart';

/// The dashboard's push-queue and sessions collectors, against a real database.
///
/// Two things here are load-bearing beyond "the numbers add up".
///
/// **`expires_at` is epoch milliseconds.** Every `dateTime` column is, because
/// that is what `DateTimeTransformer` writes. The active-sessions count used to
/// compare it against a *seconds* value, and the failure mode was silent and
/// total: any stored millisecond timestamp is ~1000x a current seconds one, so
/// every comparison passed and the whole un-swept table read as people signed
/// in. `_delete_expired_jwts` only sweeps at 04:00, so on a busy deployment
/// that is a day's worth of dead tokens counted as sessions. The
/// expired-vs-live test below is the one that would have caught it.
///
/// **The push panel must not invent a delivery.** `DrainPushJobsResponse.sent`
/// is not persisted anywhere, so the last-drain report can only say when it ran
/// and whether it broke. What *is* persisted is each job's own `delivered`
/// counter, and the test below pins that those are summed as recipients rather
/// than reported as a job count.
void main() {
  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  late io.Directory projectRoot;
  late Settings settings;

  setUp(() async {
    projectRoot = await io.Directory.systemTemp.createTemp('zonai_dash_');
    io.File('${projectRoot.path}/zonai.yaml').writeAsStringSync('name: test\n');
    io.Directory(
      '${projectRoot.path}/.zonai/migrations',
    ).createSync(recursive: true);
    settings = await runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
  });

  tearDown(() async {
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  Future<T> withScope<T>(Future<T> Function() body) => runMergedScopedFuture(
    body,
    override: {
      fsProvider.overrideWith(LocalFileSystem.new),
      loggerProvider.overrideWith(
        () => Logger(
          level: .warning,
          stdout: io.IOSink(_NullSink()),
          stderr: io.IOSink(_NullSink()),
        ),
      ),
      settingsProvider.overrideWith(() => settings),
      processProvider,
      cleanUpProvider,
      executableStopProvider,
      migrateProvider,
    },
  );

  Jwt adminJwt() => Jwt(
    userId: UnknownId('u'),
    table: '_user',
    jwtId: JwtId('j'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const {},
    claims: const {},
    admin: const (isAdmin: true, canEdit: true),
  );

  /// Runs [body] against an open database, then collects the metrics.
  ///
  /// The collector is admin-gated, and the gate is exercised on its own below;
  /// everything else here is about the numbers.
  Future<void> withMetrics(
    Future<void> Function(dynamic db) seed,
    Future<void> Function(dynamic metrics) verify,
  ) async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        final db = await zonaiDb.open();
        await seed(db);
        await verify(await zonaiDb.dashboardMetrics(jwt: adminJwt()));
      } finally {
        await zonaiDb.dispose();
      }
    });
  }

  Future<void> insertJwt(
    dynamic db, {
    required String id,
    required String userId,
    required DateTime expiresAt,
  }) => db.execute(
    'INSERT INTO "_jwt" ("id", "user_id", "expires_at") VALUES (?, ?, ?)',
    // Milliseconds, matching what raindrop writes through this column.
    [id, userId, expiresAt.millisecondsSinceEpoch],
  );

  Future<void> insertPushJob(
    dynamic db, {
    required String id,
    required PushJobStatus status,
    int delivered = 0,
    int permanentlyRejected = 0,
    int transientlyFailed = 0,
    String? error,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.execute(
      'INSERT INTO "_push_jobs" ("id", "message", "target_table", '
      '"target_column", "status", "delivered", "permanently_rejected", '
      '"transiently_failed", "error", "created_at", "updated_at") '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        '{"title":"hi"}',
        'devices',
        'token',
        status.name,
        delivered,
        permanentlyRejected,
        transientlyFailed,
        error,
        now,
        (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      ],
    );
  }

  group('sessions', () {
    test('counts only sessions that have not expired', () async {
      await withMetrics(
        (db) async {
          final now = DateTime.now();
          // Two live, one expired an hour ago. The expired row is still in the
          // table because `_delete_expired_jwts` runs at 04:00, which is
          // exactly the state the count has to survive.
          await insertJwt(
            db,
            id: 'live1',
            userId: 'alice',
            expiresAt: now.add(const Duration(hours: 5)),
          );
          await insertJwt(
            db,
            id: 'live2',
            userId: 'alice',
            expiresAt: now.add(const Duration(hours: 5)),
          );
          await insertJwt(
            db,
            id: 'dead',
            userId: 'bob',
            expiresAt: now.subtract(const Duration(hours: 1)),
          );
        },
        (metrics) async {
          expect(
            metrics.sessions.active,
            2,
            reason:
                'the expired row is not a session. Comparing a milliseconds '
                'column against a seconds value made every row pass, which '
                'reported 3 here and is the bug this pins',
          );
          expect(
            metrics.activeSessions,
            metrics.sessions.active,
            reason:
                'the top-level wire field and the panel read one query -- two '
                'counts of the same thing are two chances to disagree',
          );
          expect(
            metrics.sessions.distinctUsers,
            1,
            reason:
                "bob's only session is expired, so he is not signed in -- and "
                "alice's two sessions are one user, not two",
          );
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'separates expiring-soon from active without double counting',
      () async {
        await withMetrics(
          (db) async {
            final now = DateTime.now();
            await insertJwt(
              db,
              id: 'soon',
              userId: 'alice',
              expiresAt: now.add(const Duration(minutes: 20)),
            );
            await insertJwt(
              db,
              id: 'later',
              userId: 'bob',
              expiresAt: now.add(const Duration(hours: 9)),
            );
          },
          (metrics) async {
            expect(metrics.sessions.active, 2);
            expect(
              metrics.sessions.expiringWithinHour,
              1,
              reason: 'a subset of active, never a separate population',
            );
            expect(
              metrics.sessions.expiringWithinHour,
              lessThanOrEqualTo(metrics.sessions.active),
            );
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('ranks top users by live sessions only', () async {
      await withMetrics(
        (db) async {
          final now = DateTime.now();
          for (var i = 0; i < 3; i++) {
            await insertJwt(
              db,
              id: 'a$i',
              userId: 'alice',
              expiresAt: now.add(const Duration(hours: 4)),
            );
          }
          await insertJwt(
            db,
            id: 'b0',
            userId: 'bob',
            expiresAt: now.add(const Duration(hours: 4)),
          );
          // Five expired rows for carol: a ranking that counted rows rather
          // than sessions would put her top.
          for (var i = 0; i < 5; i++) {
            await insertJwt(
              db,
              id: 'c$i',
              userId: 'carol',
              expiresAt: now.subtract(const Duration(days: 1)),
            );
          }
        },
        (metrics) async {
          expect(metrics.sessions.topUsers.map((u) => u.userId), [
            'alice',
            'bob',
          ], reason: 'carol holds five rows and zero sessions');
          expect(metrics.sessions.topUsers.first.sessionCount, 3);
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('reports the no-sessions state as zero, not as an error', () async {
      await withMetrics((db) async {}, (metrics) async {
        expect(metrics.sessions.active, 0);
        expect(metrics.sessions.expiringWithinHour, 0);
        expect(metrics.sessions.distinctUsers, 0);
        expect(
          metrics.sessions.topUsers,
          isEmpty,
          reason:
              'a deployment nobody has signed in to is the normal first state, '
              'not a fault -- and SUM over no rows is NULL, which must land as '
              '0 rather than throwing',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('push queue', () {
    test('reports depth per status rather than one total', () async {
      await withMetrics(
        (db) async {
          await insertPushJob(db, id: 'p1', status: PushJobStatus.pending);
          await insertPushJob(db, id: 'p2', status: PushJobStatus.pending);
          await insertPushJob(db, id: 'r1', status: PushJobStatus.running);
          await insertPushJob(db, id: 'c1', status: PushJobStatus.completed);
          await insertPushJob(
            db,
            id: 'f1',
            status: PushJobStatus.failed,
            error: 'APNs said 410',
          );
        },
        (metrics) async {
          final queue = metrics.pushQueue;
          expect(queue.pending, 2);
          expect(queue.running, 1);
          expect(queue.completed, 1);
          expect(queue.failed, 1);
          expect(
            queue.outstanding,
            3,
            reason:
                'work still to do is pending + running. Folding the finished '
                'jobs in would keep this non-zero for the seven days retention '
                'holds them, so it could never signal a backlog',
          );
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'sums recipient counters, which a job count cannot substitute for',
      () async {
        await withMetrics(
          (db) async {
            await insertPushJob(
              db,
              id: 'c1',
              status: PushJobStatus.completed,
              delivered: 900,
              permanentlyRejected: 40,
              transientlyFailed: 3,
            );
            await insertPushJob(
              db,
              id: 'c2',
              status: PushJobStatus.completed,
              delivered: 100,
              permanentlyRejected: 2,
            );
            // A job that reached nobody. It still counts toward depth, and must
            // not move the delivered figure.
            await insertPushJob(db, id: 'p1', status: PushJobStatus.pending);
          },
          (metrics) async {
            final queue = metrics.pushQueue;
            expect(
              queue.delivered,
              1000,
              reason:
                  'recipients across every retained job, summed over statuses -- '
                  'three jobs is not a thousand notifications, which is the whole '
                  'reason this number exists',
            );
            expect(queue.permanentlyRejected, 42);
            expect(queue.transientlyFailed, 3);
            expect(queue.completed, 2);
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('lists failed jobs with their error, newest first', () async {
      await withMetrics(
        (db) async {
          final now = DateTime.now();
          await insertPushJob(
            db,
            id: 'old',
            status: PushJobStatus.failed,
            error: 'no push config',
            delivered: 0,
            updatedAt: now.subtract(const Duration(hours: 2)),
          );
          await insertPushJob(
            db,
            id: 'recent',
            status: PushJobStatus.failed,
            error: 'FCM 401 after 40000 recipients',
            delivered: 40000,
            updatedAt: now,
          );
        },
        (metrics) async {
          final failures = metrics.pushQueue.failedJobs;
          expect(failures.map((f) => f.id), ['recent', 'old']);
          expect(failures.first.error, 'FCM 401 after 40000 recipients');
          expect(
            failures.first.delivered,
            40000,
            reason:
                'delivered travels with the error: a job that failed having '
                'reached 40,000 people cannot be re-sent, and one that reached '
                'nobody can. The error text alone does not say which',
          );
          expect(failures.last.delivered, 0);
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'reports the empty queue as idle rather than as missing data',
      () async {
        await withMetrics((db) async {}, (metrics) async {
          final queue = metrics.pushQueue;
          expect(queue.pending, 0);
          expect(queue.running, 0);
          expect(queue.completed, 0);
          expect(queue.failed, 0);
          expect(queue.outstanding, 0);
          expect(queue.delivered, 0);
          expect(queue.failedJobs, isEmpty);
          expect(
            queue.lastDrain,
            isNull,
            reason:
                'never drained is null, not a run at the epoch -- those would '
                'render the same and mean opposite things',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'reads the last drain from _cron_jobs, and claims no send count',
      () async {
        await withMetrics(
          (db) async {
            final now = DateTime.now();
            // An older successful run and a newer failed one. The newest wins,
            // and its error has to survive to the panel.
            await db.execute(
              'INSERT INTO "_cron_jobs" ("id", "name", "started", "completed", '
              '"failed", "error", "stack_trace") VALUES (?, ?, ?, ?, ?, ?, ?)',
              [
                'cr1',
                '_drain_push_jobs',
                now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
                now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
                null,
                null,
                null,
              ],
            );
            await db.execute(
              'INSERT INTO "_cron_jobs" ("id", "name", "started", "completed", '
              '"failed", "error", "stack_trace") VALUES (?, ?, ?, ?, ?, ?, ?)',
              [
                'cr2',
                '_drain_push_jobs',
                now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
                null,
                now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
                'APNs transport unreachable',
                null,
              ],
            );
            // A different cron, which must not be mistaken for the drain.
            await db.execute(
              'INSERT INTO "_cron_jobs" ("id", "name", "started", "completed", '
              '"failed", "error", "stack_trace") VALUES (?, ?, ?, ?, ?, ?, ?)',
              [
                'cr3',
                '_cleanup_logs',
                now.millisecondsSinceEpoch,
                now.millisecondsSinceEpoch,
                null,
                null,
                null,
              ],
            );
          },
          (metrics) async {
            final drain = metrics.pushQueue.lastDrain;
            expect(drain, isNotNull);
            expect(
              drain!.succeeded,
              isFalse,
              reason:
                  'the most recent drain failed; the older success is history',
            );
            expect(drain.inProgress, isFalse);
            expect(drain.error, 'APNs transport unreachable');
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('treats a drain with no outcome yet as in progress', () async {
      await withMetrics(
        (db) async {
          await db.execute(
            'INSERT INTO "_cron_jobs" ("id", "name", "started", "completed", '
            '"failed", "error", "stack_trace") VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              'cr1',
              '_drain_push_jobs',
              DateTime.now().millisecondsSinceEpoch,
              null,
              null,
              null,
              null,
            ],
          );
        },
        (metrics) async {
          final drain = metrics.pushQueue.lastDrain!;
          expect(
            drain.inProgress,
            isTrue,
            reason:
                'the drain fires every minute, so catching one mid-run is '
                'ordinary -- reporting it as failed would cry wolf once a minute',
          );
          expect(drain.succeeded, isFalse);
        },
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  test('refuses a caller who is not an admin', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await zonaiDb.open();

        // The push queue names every failure reason on the deployment and the
        // sessions panel names user ids. Both are operator information, and the
        // engine refusing on its own is what makes the endpoint's gate a second
        // lock rather than the only one.
        await expectLater(
          zonaiDb.dashboardMetrics(
            jwt: Jwt(
              userId: UnknownId('u'),
              table: '_user',
              jwtId: JwtId('j'),
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
              user: const {},
              claims: const {},
              admin: const (isAdmin: false, canEdit: null),
            ),
          ),
          throwsA(isA<TableAccessDeniedException>()),
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Swallows log output; these tests assert on returned values, not on logs.
class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
