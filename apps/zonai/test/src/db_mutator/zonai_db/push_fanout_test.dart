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
import 'package:zonai/src/push/fcm_push_courier.dart';
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
import '../../push/fake_fcm.dart';

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
      <
        ({
          String id,
          String token,
          String? rowToken,
          PushRejectionReason reason,
        })
      >[];

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

  /// Which permanent reason [rejectTokens] come back as. `unregistered` is
  /// the ordinary case; `invalidArgument` is the one that can mean the
  /// *message* was wrong rather than the token.
  PushRejectionReason rejectWith = PushRejectionReason.unregistered;

  /// Called with each message handed to the transport, so a test can assert
  /// which notification a given job actually sent.
  void Function(PushMessage message)? onMessage;

  /// Runs while a batch is "in flight", before its outcomes are committed.
  /// The stand-in for anything that writes to the table mid-batch — a device
  /// re-registering being the one that matters.
  Future<void> Function()? duringSend;

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

    onMessage?.call(message);
    sentBatches.add(List.of(tokens));
    _tokensSeen += tokens.length;

    if (duringSend case final hook?) await hook();

    return [
      for (final token in tokens)
        if (rejectTokens.contains(token))
          PushPermanentlyRejected(token: token, reason: rejectWith)
        else if (failTokens.contains(token))
          PushTransientlyFailed(token: token, detail: 'fake timeout')
        else
          PushDelivered(token: token),
    ];
  }

  List<String> get allSentTokens => [for (final batch in sentBatches) ...batch];

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
  // Ignored by `FakePushCourier`, which never parses them. The end-to-end
  // group overrides both because a real `FcmPushCourier` does parse them, and
  // signs an assertion with what it finds.
  String projectId = 'fixture-project',
  PushCredentials credentials = const PushCredentials.inline('{}'),
}) => PushConfig(
  projectId: projectId,
  credentials: credentials,
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

  /// Bound in place of [courier] when set. The end-to-end group puts a real
  /// [FcmPushCourier] here so the same engine runs against a real socket.
  ///
  /// Deliberately an override rather than a variable the scope reads
  /// directly: several tests replace [courier] *after* `setUp` has run, and a
  /// scope holding the old instance would quietly send to a courier nobody
  /// configured — which is a green test asserting nothing.
  PushCourier? overrideCourier;

  setUp(() {
    extension = RecordingExtension();
    courier = FakePushCourier();
    overrideCourier = null;

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
        pushCourierProvider.overrideWith(() => overrideCourier ?? courier),
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

  test(
    'a fan-out larger than one pass continues without waiting for the cron',
    () async {
      // 50 recipients at batchSize 2 is 25 batches, past the 20-batch ceiling
      // one pass will commit. That ceiling exists so a large fan-out cannot
      // starve the queue behind it — not to rate-limit it. Without a chained
      // continuation the remaining recipients would sit until the next minute
      // boundary, turning a fairness bound into a silent throttle.
      await run(_appConfigWith(_pushConfig(batchSize: 2)), (zonaiDb) async {
        await seed(zonaiDb, count: 50);

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );

        // Drains chain, so awaiting one that was requested after the
        // continuation was scheduled means the continuation has finished.
        await zonaiDb.drainPushJobs();
        await zonaiDb.drainPushJobs();

        final entry = await job(zonaiDb, id!);
        expect(
          entry.status,
          PushJobStatus.completed,
          reason:
              'the job passed the per-pass batch ceiling; nothing but the '
              'continuation would have finished it before the cron ran',
        );
        expect(entry.delivered, 50);
        expect(courier.allSentTokens.toSet(), hasLength(50));
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
        HostWorkerRegistries.extensions = DbExtensions(extensions: [extension]);

        await run(_appConfigWith(_pushConfig(onPermanentRejection: setting)), (
          zonaiDb,
        ) async {
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
        });
      }
    },
  );

  test(
    'a whole batch rejected as INVALID_ARGUMENT does not wipe the table',
    () async {
      // FCM returns INVALID_ARGUMENT for a bad *token* and for a bad
      // *message* alike — an over-limit payload, a malformed data key. The
      // second case fails identically for every recipient, so classifying it
      // per-token prunes the entire batch because the author wrote one
      // notification wrong. Under `deleteRow` that is the whole table.
      //
      // Every token being individually invalid at the same moment is not a
      // real failure mode; one bad message is. Failing the job and saying so
      // is the right answer in both readings.
      await run(_appConfigWith(_pushConfig(batchSize: 10)), (zonaiDb) async {
        await seed(zonaiDb, count: 5);
        courier.rejectTokens.addAll([
          for (var i = 0; i < 5; i++) 'tok-d${i.toString().padLeft(6, '0')}',
        ]);
        courier.rejectWith = PushRejectionReason.invalidArgument;

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        final after = await rows(zonaiDb);
        expect(
          after.where((r) => r.token != null),
          hasLength(5),
          reason:
              'one malformed message must not clear every recipient in the '
              'batch — this is self-inflicted, silent, total data loss',
        );

        final entry = await job(zonaiDb, id!);
        expect(entry.status, PushJobStatus.failed);
        expect(entry.error, contains('INVALID_ARGUMENT'));
      });
    },
  );

  test('a whole batch that is genuinely UNREGISTERED still prunes', () async {
    // The guard above must stay narrow. An old cohort whose app was
    // uninstalled really can be a full batch of dead tokens, and refusing
    // to prune those would leave a table that never drains.
    await run(_appConfigWith(_pushConfig(batchSize: 10)), (zonaiDb) async {
      await seed(zonaiDb, count: 5);
      courier.rejectTokens.addAll([
        for (var i = 0; i < 5; i++) 'tok-d${i.toString().padLeft(6, '0')}',
      ]);

      await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      final after = await rows(zonaiDb);
      expect(after.where((r) => r.token != null), isEmpty);
    });
  });

  test(
    'a transient failure is counted, distinctly, and never prunes',
    () async {
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
    },
  );

  test('a device that re-registers mid-batch keeps its new token', () async {
    // The race the prune's token match exists for. Between reading a batch
    // and committing it, the device wipes and registers again, writing a
    // NEW token into the same row. FCM then rejects the OLD one — which is
    // correct, it is dead — and a prune keyed on the primary key alone
    // would clear the live registration that replaced it. The user stops
    // receiving notifications, and nothing anywhere records why.
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);
      courier.rejectTokens.add('tok-d000001');
      courier.duringSend = () async {
        final db = await zonaiDb.open();
        await db.execute(
          'UPDATE "device_tokens" SET "token" = ? WHERE "id" = ?',
          ['tok-d000001-REREGISTERED', 'd000001'],
        );
      };

      await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      final after = await rows(zonaiDb);
      expect(
        after[1].token,
        'tok-d000001-REREGISTERED',
        reason:
            'the row was pruned on a token that is no longer in it — the '
            'prune must match the token it was told about, not just the key',
      );
    });
  });

  test('deleteRow also refuses to delete a row that re-registered', () async {
    // The same race, with the destructive policy — where getting it wrong
    // removes the row rather than a column.
    await run(
      _appConfigWith(
        _pushConfig(onPermanentRejection: OnPermanentRejection.deleteRow),
      ),
      (zonaiDb) async {
        await seed(zonaiDb, count: 3);
        courier.rejectTokens.add('tok-d000001');
        courier.duringSend = () async {
          final db = await zonaiDb.open();
          await db.execute(
            'UPDATE "device_tokens" SET "token" = ? WHERE "id" = ?',
            ['tok-d000001-REREGISTERED', 'd000001'],
          );
        };

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
        expect(after[1].token, 'tok-d000001-REREGISTERED');
      },
    );
  });

  test('several queued jobs all drain, none left behind', () async {
    await run(_appConfigWith(_pushConfig(batchSize: 50)), (zonaiDb) async {
      await seed(zonaiDb, count: 4);

      final ids = <PushJobId>[];
      for (var i = 0; i < 3; i++) {
        final id = await zonaiDb.enqueuePush(
          message: PushMessage(title: 'n$i', body: 'b$i'),
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        ids.add(id!);
      }
      await zonaiDb.drainPushJobs();

      for (final id in ids) {
        expect((await job(zonaiDb, id)).status, PushJobStatus.completed);
      }
      expect(
        courier.allSentTokens,
        hasLength(12),
        reason:
            '3 jobs x 4 recipients. Deliberately not asserting these land in '
            'ONE pass: each enqueue kicks its own drain, so the split across '
            'passes is timing. What must hold is that no job is skipped.',
      );
    });
  });

  test('each job sends its own message, not the first one enqueued', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 1);

      final sentMessages = <String>[];
      courier.onMessage = (m) => sentMessages.add(m.title);

      for (final title in ['alpha', 'beta']) {
        await zonaiDb.enqueuePush(
          message: PushMessage(title: title, body: 'b'),
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
      }
      await zonaiDb.drainPushJobs();

      expect(
        sentMessages,
        ['alpha', 'beta'],
        reason:
            'the message is stored per job; a fan-out reading the wrong row '
            "would send one notification's text under another's job",
      );
    });
  });

  test(
    'a job whose token column vanishes fails rather than spinning',
    () async {
      await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
        await seed(zonaiDb, count: 3);

        // The schema moves out from under the job BEFORE it is enqueued, so
        // this does not depend on winning a race with the enqueue-time drain
        // kick — the drain fails on the same missing column whichever pass
        // reaches it first. Enqueue still succeeds: its shape check reads the
        // registered schema, which is exactly the drift being simulated.
        final db = await zonaiDb.open();
        await db.execute('DROP TABLE "device_tokens"');
        await db.execute(
          'CREATE TABLE "device_tokens" ("id" TEXT PRIMARY KEY, '
          '"user_id" TEXT NOT NULL, "label" TEXT NOT NULL)',
        );

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );

        await zonaiDb.drainPushJobs();

        // Nothing here can be retried into success, so it must fail loudly
        // rather than be retried every minute forever.
        final entry = await job(zonaiDb, id!);
        expect(entry.status, PushJobStatus.failed);
        expect(entry.error, isNotNull);
        expect(courier.allSentTokens, isEmpty);
      });
    },
  );

  test('a failed job is not picked up again by the next drain', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);
      courier.throwAfterTokens = 0;

      await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: null,
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      final sentAfterFirst = courier.allSentTokens.length;
      await zonaiDb.drainPushJobs();
      await zonaiDb.drainPushJobs();

      expect(
        courier.allSentTokens.length,
        sentAfterFirst,
        reason:
            'a failed job that stayed in the pending set would be retried '
            'once a minute forever, against whatever broke it',
      );
    });
  });

  test('an empty recipient set completes rather than hanging', () async {
    await run(_appConfigWith(_pushConfig()), (zonaiDb) async {
      await seed(zonaiDb, count: 3);

      final id = await zonaiDb.enqueuePush(
        message: message,
        table: 'device_tokens',
        column: 'token',
        where: const Eq('user_id', 'nobody'),
        jwt: CronJwt(),
      );
      await zonaiDb.drainPushJobs();

      final entry = await job(zonaiDb, id!);
      expect(entry.status, PushJobStatus.completed);
      expect(entry.delivered, 0);
      expect(courier.sentBatches, isEmpty);
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

  test(
    'a missing AppConfig.push enqueues nothing and does not throw',
    () async {
      await run(_appConfigWithoutPush, (zonaiDb) async {
        await seed(zonaiDb, count: 3);

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );

        expect(id, isNull, reason: 'a missing config must be loud, not fatal');

        final db = await zonaiDb.open();
        final count = await db.execute('SELECT COUNT(*) FROM "_push_jobs"');
        expect(count.rows.single.first, 0);

        final drained = await zonaiDb.drainPushJobs();
        expect(drained.skipped, isNotNull);
        expect(courier.allSentTokens, isEmpty);
      });
    },
  );

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

  /// The engine and the real transport, running together for the first time.
  ///
  /// Everything above this point substitutes `PushCourier`, so the seam
  /// between "the engine decided to prune" and "FCM said this token is dead"
  /// has never been crossed by a test: the fake is *told* which tokens to
  /// reject, in the engine's own vocabulary. Here FCM's own wire format is
  /// what decides, and the engine has to read it correctly through
  /// `FcmPushCourier` — a real OAuth2 exchange, a real signed assertion, a
  /// real socket — before a single row is touched.
  ///
  /// That makes this the only place where a mistake in `_classify` shows up
  /// as *the wrong row being cleared* rather than as a mismatched enum.
  group('end to end, over a real socket', () {
    late FakeFcm fcm;

    /// Boots a fake FCM and points a real courier at it, returning the config
    /// that names it. Null when there is no `openssl` to sign with.
    Future<AppConfig?> boot({
      OnPermanentRejection onPermanentRejection =
          OnPermanentRejection.clearColumn,
      int batchSize = 10,
    }) async {
      final keys = generateKeypair();
      if (keys == null) {
        markTestSkipped('openssl is not on PATH, so nothing could be signed');
        return null;
      }

      fcm = await FakeFcm.start(publicKeyPem: keys.public);
      final real = FcmPushCourier(
        fileSystem: const LocalFileSystem(),
        baseUri: fcm.baseUri,
      );
      overrideCourier = real;
      addTearDown(() async {
        await real.close();
        await fcm.stop();
      });

      return _appConfigWith(
        _pushConfig(
          onPermanentRejection: onPermanentRejection,
          batchSize: batchSize,
          projectId: 'e2e-project',
          credentials: PushCredentials.inline(
            serviceAccountJson(
              privateKey: keys.private,
              tokenUri: fcm.tokenUri,
              projectId: 'e2e-project',
            ),
          ),
        ),
      );
    }

    test('a fan-out reaches the wire and completes', () async {
      final config = await boot();
      if (config == null) return;

      await run(config, (zonaiDb) async {
        await seed(zonaiDb, count: 5);

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        expect(
          fcm.sentTokens..sort(),
          [for (var i = 0; i < 5; i++) 'tok-d${i.toString().padLeft(6, '0')}']
            ..sort(),
          reason: 'every seeded token should have reached the endpoint',
        );
        expect(
          fcm.tokenRequests,
          hasLength(1),
          reason: 'one OAuth2 exchange serves the whole fan-out',
        );

        final entry = await job(zonaiDb, id!);
        expect(entry.status, PushJobStatus.completed);
        expect(entry.delivered, 5);
        expect(entry.permanentlyRejected, 0);
      });
    });

    test("FCM's own UNREGISTERED is what clears the row", () async {
      final config = await boot();
      if (config == null) return;

      // Nothing here speaks the engine's vocabulary. The only input is the
      // JSON body FCM documents for a dead token, and the row being cleared
      // is downstream of parsing it correctly.
      fcm.replyFor = (token) =>
          token == 'tok-d000002' ? errReply(404, 'UNREGISTERED') : okReply;

      await run(config, (zonaiDb) async {
        await seed(zonaiDb, count: 5);

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        final after = await rows(zonaiDb);
        expect(
          after.firstWhere((r) => r.id == 'd000002').token,
          isNull,
          reason: 'the dead token is the one that gets cleared',
        );
        expect(
          [
            for (final r in after)
              if (r.token != null) r.id,
          ],
          ['d000000', 'd000001', 'd000003', 'd000004'],
          reason:
              'and only that one — a classifier that widened its net would '
              'show up here as live devices losing their registration',
        );

        final entry = await job(zonaiDb, id!);
        expect(entry.delivered, 4);
        expect(entry.permanentlyRejected, 1);
      });
    });

    test('a transient wire failure counts, and never prunes', () async {
      final config = await boot();
      if (config == null) return;

      fcm.replyFor = (token) =>
          token == 'tok-d000001' ? errReply(503, 'UNAVAILABLE') : okReply;

      await run(config, (zonaiDb) async {
        await seed(zonaiDb, count: 3);

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        expect(
          [for (final r in await rows(zonaiDb)) r.token],
          isNot(contains(isNull)),
          reason:
              'a server having a bad minute is not a device that uninstalled '
              'the app, and treating it as one costs that device every future '
              'notification',
        );

        final entry = await job(zonaiDb, id!);
        expect(entry.transientlyFailed, 1);
        expect(entry.permanentlyRejected, 0);
      });
    });

    test('bad credentials fail the job without blaming a device', () async {
      final config = await boot();
      if (config == null) return;

      // The token endpoint issues one value and the send endpoint demands
      // another: a rotated or wrongly-scoped key, seen from the courier.
      fcm.acceptedAccessToken = 'not-the-one-that-was-issued';
      fcm.replyFor = (_) => okReply;

      await run(config, (zonaiDb) async {
        await seed(zonaiDb, count: 4);

        final id = await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        expect(
          [for (final r in await rows(zonaiDb)) r.token],
          isNot(contains(isNull)),
          reason:
              'this is the whole point of throwing on 401 rather than '
              'classifying it: a config mistake must not cost every '
              'recipient in the batch their registration',
        );

        final entry = await job(zonaiDb, id!);
        expect(entry.status, PushJobStatus.failed);
        expect(entry.error, isNotNull);
      });
    });

    test('paging across batches reuses one access token', () async {
      final config = await boot(batchSize: 4);
      if (config == null) return;

      await run(config, (zonaiDb) async {
        await seed(zonaiDb, count: 10);

        await zonaiDb.enqueuePush(
          message: message,
          table: 'device_tokens',
          column: 'token',
          where: null,
          jwt: CronJwt(),
        );
        await zonaiDb.drainPushJobs();

        expect(fcm.sends, hasLength(10));
        expect(
          fcm.sentTokens.toSet(),
          hasLength(10),
          reason: 'the cursor advanced; no page was re-read',
        );
        expect(
          fcm.tokenRequests,
          hasLength(1),
          reason:
              'the cache lives on the courier, so a fan-out that outlives one '
              'batch must not re-mint per batch',
        );
      });
    });
  });
}
