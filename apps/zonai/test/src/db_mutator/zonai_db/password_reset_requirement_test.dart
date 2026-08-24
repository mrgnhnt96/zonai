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
import 'package:zonai_schema/src/internal/tables/jwt_table.dart';
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../../../support/temp_directory.dart';

/// The requirement row's own semantics, against a real [ZonaiDb].
///
/// **What this file cannot reach, and why it is not a gap being hidden.**
/// [ZonaiDb.requirePasswordReset] resolves the account by email, which goes
/// through `_authRecord` -> `ViewAuthOperationRequest`, and reads the id and
/// password column names through `GetColumnNameRequest`. All three need a
/// compiled *operations* worker, and a project this bare has none -- the same
/// boundary `api_token_resolution_test.dart` states for bound tokens. So the
/// assertions that need an email to resolve (set on an OAuth-only table
/// throws; setting by email revokes that account's sessions) live in the e2e
/// suite, where a compiled project exists.
///
/// What IS reachable here is the part those assertions rest on: that a
/// requirement is one row per account, that the lookup the sign-in gate
/// performs finds it, that clearing removes it, and that revocation empties
/// the session table. Testing those against the real schema is worth more
/// than mocking the worker to restate them.
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
    projectRoot = await io.Directory.systemTemp.createTemp('zonai_prq_');
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

  void dbTest(String description, Future<void> Function(ZonaiDb db) body) {
    test(description, () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          await zonaiDb.open();
          await body(zonaiDb);
        } finally {
          await zonaiDb.dispose();
        }
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  Future<void> insertRequirement(
    ZonaiDb zonaiDb, {
    required String table,
    required String userId,
    PasswordResetReason reason = PasswordResetReason.adminForced,
    String? createdBy,
  }) async {
    final db = await zonaiDb.open();
    await db.insert(into: passwordResetRequirements).values([
      PasswordResetRequirement(
        id: PasswordResetRequirementId.generate(),
        table: table,
        userId: UnknownId(userId),
        reason: reason,
        createdBy: createdBy,
      ),
    ]);
  }

  group('the lookup the sign-in gate performs', () {
    dbTest('finds nothing for an account that owes nothing', (zonaiDb) async {
      final found = await zonaiDb.passwordResetRequirement(
        table: 'users',
        userId: 'usr_1',
      );

      expect(found, isNull);
    });

    dbTest('finds the row, carrying the reason the client is told', (
      zonaiDb,
    ) async {
      await insertRequirement(
        zonaiDb,
        table: 'users',
        userId: 'usr_1',
        reason: PasswordResetReason.temporaryPassword,
        createdBy: 'cli',
      );

      final found = await zonaiDb.passwordResetRequirement(
        table: 'users',
        userId: 'usr_1',
      );

      expect(found, isNotNull);
      expect(found!.reason, PasswordResetReason.temporaryPassword);
      expect(found.createdBy, 'cli');
      expect(found.table, 'users');
    });

    // The key is BOTH columns, not just the user id. Two auth collections can
    // hold rows with the same id, and a requirement set on one must not gate
    // a sign-in against the other.
    dbTest('is scoped to the collection, not just the user id', (
      zonaiDb,
    ) async {
      await insertRequirement(zonaiDb, table: 'users', userId: 'usr_1');

      final other = await zonaiDb.passwordResetRequirement(
        table: 'staff',
        userId: 'usr_1',
      );

      expect(other, isNull);
    });
  });

  group('one requirement per account', () {
    // The idempotency the mutator's delete-then-insert relies on is enforced
    // by the schema, not by the mutator being careful. If this index ever
    // stopped being unique, setting a requirement twice would leave two rows
    // and a single clear would remove only one -- an account left gated with
    // nothing visible explaining why.
    dbTest('a second row for the same account is refused by the index', (
      zonaiDb,
    ) async {
      await insertRequirement(zonaiDb, table: 'users', userId: 'usr_1');

      await expectLater(
        insertRequirement(zonaiDb, table: 'users', userId: 'usr_1'),
        throwsA(anything),
      );
    });

    dbTest('the same user id in a different collection is allowed', (
      zonaiDb,
    ) async {
      await insertRequirement(zonaiDb, table: 'users', userId: 'usr_1');
      await insertRequirement(zonaiDb, table: 'staff', userId: 'usr_1');

      final users = await zonaiDb.passwordResetRequirement(
        table: 'users',
        userId: 'usr_1',
      );
      final staff = await zonaiDb.passwordResetRequirement(
        table: 'staff',
        userId: 'usr_1',
      );

      expect(users, isNotNull);
      expect(staff, isNotNull);
    });
  });

  group('revocation', () {
    // Setting a requirement is only half a control: the sessions the old
    // password already minted have to go, or the account stays reachable by
    // whoever holds one for the rest of jwtExpiresIn. This asserts the
    // mechanism the mutator calls into, on the table it empties.
    dbTest('emptying an account\'s sessions leaves other accounts alone', (
      zonaiDb,
    ) async {
      final db = await zonaiDb.open();
      await db.insert(into: jwts).values([
        JwtEntry(
          id: JwtId.generate(),
          userId: const UnknownId('usr_1'),
          expiresAt: DateTime.now().add(const Duration(days: 14)),
        ),
        JwtEntry(
          id: JwtId.generate(),
          userId: const UnknownId('usr_1'),
          expiresAt: DateTime.now().add(const Duration(days: 14)),
        ),
        JwtEntry(
          id: JwtId.generate(),
          userId: const UnknownId('usr_2'),
          expiresAt: DateTime.now().add(const Duration(days: 14)),
        ),
      ]);

      await db.delete(from: jwts).where(
            jwts.userId.equals(const UnknownId('usr_1')),
          );

      final remaining = await db.select().from(jwts);

      expect(remaining, hasLength(1));
      expect(remaining.single.userId.value, 'usr_2');
    });
  });
}

class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
