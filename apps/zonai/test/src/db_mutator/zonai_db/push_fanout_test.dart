import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/push/push_courier.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';
import 'package:zonai_schema/src/handlers/rules/db_rules.dart';
import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger, Table;
import 'package:zonai_schema/zonai_schema.dart' as schema show Table;

import '../../../support/temp_directory.dart';

/// The fan-out, driven end to end against a real database and a fake
/// transport.
///
/// **Why there is no compiled fixture project here.** The engine needs three
/// things a project normally supplies through worker processes — schema
/// shapes, compiled SQL, and extension dispatch. [HostWorkerRegistries] is
/// the same door `project_main` uses to hand those to the host in-process, so
/// the fixture below registers them directly. That buys a hermetic test with
/// no `pub get` and no `zonai compile` (compare `cleanup_photos_paging_test`,
/// which pays ~17s for one), and — the part that matters more — it lets the
/// `onPushRejected` assertion observe the hook *in memory* rather than
/// inferring it from a side effect a worker process left on disk.
///
/// **What this does not cover, said out loud:** the IPC path. Everything here
/// runs in one process, so a request that serializes wrong on the wire passes
/// these tests. That gap is covered separately by the round-trip tests in
/// `libs/zonai_schema/test/src/handlers/push_message_test.dart`, which is
/// where §12's "PushMessage survives a JSON round trip" assertion lives.

/// A device token row. Deliberately not on a `users`-shaped table: `deleteRow`
/// has to be shown deleting something, and showing it on a user account is
/// how the docs would end up recommending it.
final class DeviceTokenId implements Id {
  const DeviceTokenId(this.value);

  static DeviceTokenId generate() => DeviceTokenId(Id.generate('dt'));

  @override
  final String value;

  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class DeviceToken {
  DeviceToken({
    required this.id,
    required this.userId,
    required this.token,
    required this.label,
  });

  final DeviceTokenId id;
  final String userId;
  final String? token;

  /// A column the fan-out must never read. Its value is a canary: if it ever
  /// reaches the courier or an outcome, the projection has widened.
  final String label;
}

final class DeviceTokenTable extends schema.Table<DeviceToken> {
  DeviceTokenTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: DeviceTokenId.new,
        generate: DeviceTokenId.generate,
      ),
      userId = $.text('user_id', (s) => s.userId),
      token = $.deviceToken('token', (s) => s.token),
      label = $.text('label', (s) => s.label);

  @override
  DeviceToken fromRow(RowReader read) => DeviceToken(
    id: read(id),
    userId: read(userId),
    token: read(token),
    label: read(label),
  );

  final IdColumn<DeviceTokenId> id;
  final TextColumn userId;
  final ColumnType<String?> token;
  final TextColumn label;
}

final deviceTokens = table('device_tokens', DeviceTokenTable.new);

final class DeviceTokenOperations
    extends TableOperations<DeviceTokenTable, DeviceToken> {
  DeviceTokenOperations() : super(deviceTokens);
}

final class DeviceTokenTableRules
    extends TableRules<DeviceTokenTable, DeviceToken> {
  DeviceTokenTableRules() : super(deviceTokens);
}

final class DeviceTokenRowRules
    extends RowRules<DeviceTokenTable, DeviceToken> {
  DeviceTokenRowRules() : super(deviceTokens);
}

/// Records every `onPushRejected` call, and — crucially — what the row looked
/// like *at the moment the hook ran*.
final class RecordingExtension extends Extension<DeviceToken> {
  RecordingExtension() : super(deviceTokens);

  final calls =
      <({String id, String token, String? rowToken, PushRejectionReason reason})>[];

  @override
  Future<void> onPushRejected(
    DeviceToken row,
    String token,
    PushRejectionReason reason,
    Jwt? jwt,
  ) async {
    calls.add((
      id: row.id.value,
      token: token,
      // The row as the hook received it. §5 promises the prune has not
      // happened yet, and a null here would mean it had.
      rowToken: row.token,
      reason: reason,
    ));
  }
}

/// A transport with no network.
///
/// [rejectTokens] and [failTokens] are what make outcomes controllable per
/// token, which is the only way to assert that a permanent rejection prunes
/// and a transient failure standing beside it does not.
final class FakePushCourier implements PushCourier {
  FakePushCourier();

  final sentBatches = <List<String>>[];
  final Set<String> rejectTokens = {};
  final Set<String> failTokens = {};

  /// Throws from `send` once this many tokens have been handed over — the
  /// stand-in for the process dying mid-fan-out.
  int? throwAfterTokens;
  int _tokensSeen = 0;

  Object? throwWith;

  @override
  Future<List<PushOutcome>> send(
    PushMessage message,
    List<String> tokens, {
    required PushConfig config,
  }) async {
    if (throwAfterTokens case final limit? when _tokensSeen >= limit) {
      throw throwWith ?? PushTransportException('fake transport died');
    }

    sentBatches.add(List.of(tokens));
    _tokensSeen += tokens.length;

    return [
      for (final token in tokens)
        if (rejectTokens.contains(token))
          PushPermanentlyRejected(
            token: token,
            reason: PushRejectionReason.unregistered,
          )
        else if (failTokens.contains(token))
          PushTransientlyFailed(token: token, detail: 'fake timeout')
        else
          PushDelivered(token: token),
    ];
  }

  List<String> get allSentTokens => [
    for (final batch in sentBatches) ...batch,
  ];

  @override
  Future<void> close() async {}
}

const _appConfigWithoutPush = AppConfig(
  appName: 'push-fixture',
  passwordSecret: 'test-password-secret',
  jwtSecret: 'test-jwt-secret',
);

AppConfig _appConfigWith(PushConfig push) => AppConfig(
  appName: 'push-fixture',
  passwordSecret: 'test-password-secret',
  jwtSecret: 'test-jwt-secret',
  push: push,
);

PushConfig _pushConfig({
  OnPermanentRejection onPermanentRejection = OnPermanentRejection.clearColumn,
  int batchSize = 10,
}) => PushConfig(
  projectId: 'fixture-project',
  credentials: const PushCredentials.inline('{}'),
  onPermanentRejection: onPermanentRejection,
  batchSize: batchSize,
  concurrency: 2,
  // One attempt: retries are the courier's business, and a test asserting
  // that a transient failure is *counted* should not also wait out a backoff.
  maxAttemptsPerBatch: 1,
);

void main() {
  late io.Directory projectRoot;
  late Settings settings;

  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }

    projectRoot = createCanonicalTempSync('zonai_push_fanout_');
    // ZonaiDb.open() refuses a project with no migrations directory. The app
    // table below is created by hand, so an empty one is all it needs.
    io.Directory(
      p.join(projectRoot.path, '.zonai', 'migrations'),
    ).createSync(recursive: true);
    io.File(p.join(projectRoot.path, 'zonai.yaml')).writeAsStringSync('''
version: $kVersion
''');

    settings = runMergedScoped(
      () => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
  });

  tearDownAll(() {
    HostWorkerRegistries.clear();
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  late RecordingExtension extension;
  late FakePushCourier courier;

  setUp(() {
    extension = RecordingExtension();
    courier = FakePushCourier();

    // The door `project_main` uses. Without these the host would go looking
    // for compiled worker executables that this fixture has no project to
    // build.
    HostWorkerRegistries.operations = DbOperations(
      operations: [DeviceTokenOperations()],
      tables: [deviceTokens],
    );
    HostWorkerRegistries.rules = DbRules(
      rules: [DeviceTokenTableRules(), DeviceTokenRowRules()],
    );
    HostWorkerRegistries.extensions = DbExtensions(extensions: [extension]);
  });

  Future<T> withScope<T>(AppConfig config, Future<T> Function() body) {
    return runMergedScopedFuture(
      body,
      override: {
        fsProvider.overrideWith(LocalFileSystem.new),
        loggerProvider.overrideWith(() => Logger(level: .error)),
        settingsProvider.overrideWith(() => settings),
        pushCourierProvider.overrideWith(() => courier),
        processProvider,
        cleanUpProvider,
        executableStopProvider,
        migrateProvider,
      },
    );
  }

  /// Creates `device_tokens` and seeds [count] rows.
  ///
  /// Ids are zero-padded so lexicographic order matches insertion order —
  /// which is the order a keyset cursor over the primary key walks, and
  /// therefore the order the assertions below can predict.
  Future<void> seed(ZonaiDb zonaiDb, {required int count}) async {
    final db = await zonaiDb.open();
    await db.execute('DROP TABLE IF EXISTS "device_tokens"');
    await db.execute(
      'CREATE TABLE "device_tokens" ('
      '"id" TEXT PRIMARY KEY, "user_id" TEXT NOT NULL, '
      '"token" TEXT, "label" TEXT NOT NULL)',
    );
    await db.execute('DELETE FROM "_push_jobs"');

    for (var i = 0; i < count; i++) {
      final id = 'd${i.toString().padLeft(6, '0')}';
      await db.execute(
        'INSERT INTO "device_tokens" ("id", "user_id", "token", "label") '
        'VALUES (?, ?, ?, ?)',
        [id, 'u${i % 3}', 'tok-$id', 'secret-label-$id'],
      );
    }
  }

  /// `(id, token)` for every row, in primary-key order.
  ///
  /// Read positionally rather than by name: a raw `db.execute` yields
  /// positional rows, unlike the operations layer's maps.
  Future<List<({String id, String? token})>> rows(ZonaiDb zonaiDb) async {
    final db = await zonaiDb.open();
    final result = await db.execute(
      'SELECT "id", "token" FROM "device_tokens" ORDER BY "id"',
    );
    return [
      for (final row in result.rows)
        (id: row[0]! as String, token: row[1] as String?),
    ];
  }

  Future<PushJobEntry> job(ZonaiDb zonaiDb, PushJobId id) async {
    final db = await zonaiDb.open();
    final found = await db
        .select()
        .from(pushJobs)
        .where(pushJobs.id.equals(id));
    return found.single;
  }

  const message = PushMessage(title: 'Hello', body: 'There');

  Future<void> run(
    AppConfig config,
    Future<void> Function(ZonaiDb zonaiDb) body,
  ) async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }
    await withScope(config, () async {
      // Injected rather than scope-overridden: `ZonaiDb._run` rebinds
      // `configResolverProvider` on every call, so an override out here would
      // be replaced before `_enqueuePush` ever reads it.
      final zonaiDb = ZonaiDb(configResolver: ConfigResolver.fixed(config));
      try {
        await body(zonaiDb);
      } finally {
        await zonaiDb.dispose();
      }
    });
  }

  test(
    'a recipient set larger than one batch is paged through exactly once',
    () async {
      await run(_appConfigWith(_pushConfig(batchSize: 10)), (zonaiDb) async {
        await seed(zonaiDb, count: 25);

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        final sent = courier.allSentTokens;
        expect(sent, hasLength(25));
        expect(
          sent.toSet(),
          hasLength(25),
          reason:
              'a cursor that failed to advance would re-read a page and send '
              'the same tokens again — which is exactly the duplicate the '
              'checkpoint exists to bound',
        );
        expect(courier.sentBatches.map((b) => b.length), [10, 10, 5]);

        final entry = await job(zonaiDb, id!);
        expect(entry.status, PushJobStatus.completed);
        expect(entry.delivered, 25);
      });
    },
  );

  test('rows inserted mid-scan do not cause skips', () async {
    await run(_appConfigWith(_pushConfig(batchSize: 10)), (zonaiDb) async {
      await seed(zonaiDb, count: 20);

      final id = await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();
      expect(courier.allSentTokens, hasLength(20));

      // A device registers after the fan-out finished. Its id sorts *after*
      // the cursor, so a resumed job would pick it up — the point being that
      // an OFFSET-paged scan would have mis-numbered the rows around it.
      final db = await zonaiDb.open();
      await db.execute(
        'INSERT INTO "device_tokens" ("id", "user_id", "token", "label") '
        'VALUES (?, ?, ?, ?)',
        ['d999999', 'u9', 'tok-late', 'secret-label-late'],
      );

      final entry = await job(zonaiDb, id!);
      expect(
        entry.status,
        PushJobStatus.completed,
        reason: 'the job finished before the insert; it must not reopen',
      );
      expect(
        courier.allSentTokens,
        isNot(contains('tok-late')),
        reason:
            'a completed fan-out must not pick up devices that registered '
            'after it drained',
      );
    });
  });

  test(
    'a job killed mid-fan-out resumes from its cursor and does not restart',
    () async {
      await run(_appConfigWith(_pushConfig(batchSize: 10)), (zonaiDb) async {
        await seed(zonaiDb, count: 25);

        // Die after the first batch. `PushTransportException` is the "not
        // about any one token" signal, so the cursor is left exactly where
        // the last committed batch put it.
        courier.throwAfterTokens = 10;

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        final firstPass = List.of(courier.allSentTokens);
        expect(firstPass, hasLength(10));

        final failed = await job(zonaiDb, id!);
        expect(failed.status, PushJobStatus.failed);
        expect(
          failed.cursor,
          isNotNull,
          reason: 'the cursor is the only thing that makes a resume possible',
        );

        // Bring the job back the way an operator would, and let it finish.
        final db = await zonaiDb.open();
        await db.execute(
          'UPDATE "_push_jobs" SET "status" = ?, "error" = NULL WHERE "id" = ?',
          [PushJobStatus.running.name, id.value],
        );

        courier.throwAfterTokens = null;
        await zonaiDb.drainPushJobs();

        final secondPass = courier.allSentTokens.sublist(firstPass.length);
        expect(
          secondPass,
          hasLength(15),
          reason: 'a restart from the top would re-send all 25',
        );
        expect(
          secondPass.toSet().intersection(firstPass.toSet()),
          isEmpty,
          reason:
              'this is the assertion the whole checkpointing design exists '
              'for: nothing already notified may be notified again',
        );

        final done = await job(zonaiDb, id);
        expect(done.status, PushJobStatus.completed);
        expect(
          done.delivered,
          25,
          reason:
              'counts must resume from the job row, not restart at zero on '
              'the second pass',
        );
      });
    },
  );

  test('clearColumn nulls the token and leaves the row', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);
      courier.rejectTokens.add('tok-d000001');

      await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      final after = await rows(zonaiDb);
      expect(after, hasLength(3), reason: 'clearColumn must not delete rows');
      expect(after[1].token, isNull);
      expect(after[0].token, 'tok-d000000');
      expect(after[2].token, 'tok-d000002');
    });
  });

  test('deleteRow deletes the row it was opted in to delete', () async {
    await run(
      _appConfigWith(
        _pushConfig(onPermanentRejection: OnPermanentRejection.deleteRow),
      ),
      (zonaiDb) async {
        await seed(zonaiDb, count: 3);
        courier.rejectTokens.add('tok-d000001');

        await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        final after = await rows(zonaiDb);
        expect(after, hasLength(2));
        expect(after.map((r) => r.id), ['d000000', 'd000002']);
      },
    );
  });

  test('none leaves the row completely untouched', () async {
    await run(
      _appConfigWith(
        _pushConfig(onPermanentRejection: OnPermanentRejection.none),
      ),
      (zonaiDb) async {
        await seed(zonaiDb, count: 3);
        courier.rejectTokens.add('tok-d000001');

        await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        final after = await rows(zonaiDb);
        expect(after, hasLength(3));
        expect(after[1].token, 'tok-d000001');
      },
    );
  });

  test(
    'onPushRejected fires under all three settings, before the row changes',
    () async {
      for (final setting in OnPermanentRejection.values) {
        extension = RecordingExtension();
        courier = FakePushCourier()..rejectTokens.add('tok-d000001');
        HostWorkerRegistries.extensions = DbExtensions(
          extensions: [extension],
        );

        await run(
          _appConfigWith(_pushConfig(onPermanentRejection: setting)),
          (zonaiDb) async {
            await seed(zonaiDb, count: 3);

            await zonaiDb.enqueuePush(
              message: message,
              table: 'device_tokens',
              column: 'token',
              where: null,
              jwt: CronJwt(),
            );
            await zonaiDb.drainPushJobs();

            expect(
              extension.calls,
              hasLength(1),
              reason:
                  'the hook fires under $setting too — that is what makes '
                  '`none` a usable choice rather than a silent one',
            );
            final call = extension.calls.single;
            expect(call.id, 'd000001');
            expect(call.token, 'tok-d000001');
            expect(call.reason, PushRejectionReason.unregistered);
            expect(
              call.rowToken,
              'tok-d000001',
              reason:
                  'the hook must see the row intact: under $setting the '
                  'prune has not happened yet',
            );
          },
        );
      }
    },
  );

  test('a transient failure is counted, distinctly, and never prunes', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);
      courier.failTokens.add('tok-d000001');

      final id = await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      final entry = await job(zonaiDb, id!);
      expect(entry.transientlyFailed, 1);
      expect(entry.permanentlyRejected, 0);
      expect(entry.delivered, 2);

      final after = await rows(zonaiDb);
      expect(
        after[1].token,
        'tok-d000001',
        reason:
            'a token that timed out is not a token that is dead; collapsing '
            'the two is what this feature exists to get right',
      );
      expect(
        extension.calls,
        isEmpty,
        reason: 'onPushRejected is for permanent rejections only',
      );
    });
  });

  test('a where clause narrows the recipient set', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 9);

      await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: const Eq('user_id', 'u1'),
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      expect(courier.allSentTokens, [
        'tok-d000001',
        'tok-d000004',
        'tok-d000007',
      ]);
    });
  });

  test('rows with a null token are never sent to', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);
      final db = await zonaiDb.open();
      await db.execute(
        'UPDATE "device_tokens" SET "token" = NULL WHERE "id" = ?',
        ['d000001'],
      );

      await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      expect(courier.allSentTokens, ['tok-d000000', 'tok-d000002']);
    });
  });

  test('a missing AppConfig.push enqueues nothing and does not throw', () async {
    await run(_appConfigWithoutPush, (zonaiDb) async {
      await seed(zonaiDb, count: 3);

      final id = await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );

      expect(
        id,
        isNull,
        reason: 'a missing config must be loud, not fatal',
      );

      final db = await zonaiDb.open();
      final count = await db.execute('SELECT COUNT(*) FROM "_push_jobs"');
      expect(count.rows.single.first, 0);

      final drained = await zonaiDb.drainPushJobs();
      expect(drained.skipped, isNotNull);
      expect(courier.allSentTokens, isEmpty);
    });
  });

  test('a column that is not a deviceToken column is refused', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);

      // The whole point of §2's gate: without it, `push` would be a way to
      // read any column an admin identity could name, since the recipient
      // query deliberately bypasses per-row rules.
      await expectLater(
        zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'label',
          where: null,
          jwt: CronJwt(),
        ),
        throwsA(isA<PushTargetException>()),
      );

      await expectLater(
        zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'nope',
          where: null,
          jwt: CronJwt(),
        ),
        throwsA(isA<PushTargetException>()),
      );
    });
  });

  test('a non-admin identity cannot enqueue a fan-out', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);

      await expectLater(
        zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: null,
        ),
        throwsA(isA<TableAccessDeniedException>()),
      );
    });
  });
}

