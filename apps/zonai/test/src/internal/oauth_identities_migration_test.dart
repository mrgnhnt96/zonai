import 'dart:io';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as raindrop;
import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:test/test.dart';
import 'package:zonai/src/internal/internal_db_migrate.dart';

import '../../support/temp_directory.dart';

void main() {
  setUpAll(() {
    final lib = File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  group('0006_add_oauth_identities_table_and_oauth_state_challenge', () {
    late Directory tempDir;
    late File dbFile;
    late ResqliteDelegate delegate;
    late Raindrop db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'zonai_oauth_identities_migrate_',
      );
      dbFile = File('${tempDir.path}/test.sqlite');
      delegate = await ResqliteDelegate.open(dbFile.path);
      db = Raindrop(delegate);
    });

    tearDown(() async {
      await delegate.close();
      if (tempDir.existsSync()) {
        deleteTempDirectory(tempDir);
      }
    });

    test(
      'applies cleanly on a populated database and existing rows survive',
      () async {
        // Bring the db up to just before the oauth-identities migration, as
        // if it had been running in production for a while.
        final priorMigrations = InternalDbMigrate.migrations.sublist(
          0,
          InternalDbMigrate.migrations.length - 1,
        );
        await raindrop.migrate(db, priorMigrations);

        // Populate a pre-existing table so the migration has real data to
        // migrate around, not just an empty schema.
        await db.execute(
          'INSERT INTO "_auth_challenges" '
          '("id", "table", "target", "secret_hash", "type", "expires_at", '
          '"created_at", "can_consume", "allowed_attempts") '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'existing_ach',
            'users',
            'someone@example.com',
            'hash',
            'otp',
            9999999999999,
            0,
            1,
            3,
          ],
        );

        // Now apply the rest, which includes the oauth-identities migration.
        await InternalDbMigrate.apply(db);

        final applied = await db.execute(
          'SELECT tag FROM "_raindrop_migrations" ORDER BY id',
        );
        expect(
          applied.rows.map((row) => row[0]).toList(),
          contains('0006_add_oauth_identities_table_and_oauth_state_challenge'),
        );

        // The pre-existing row is untouched.
        final challenge = await db.execute(
          'SELECT "table", "target" FROM "_auth_challenges" WHERE "id" = ?',
          ['existing_ach'],
        );
        expect(challenge.rows, hasLength(1));
        expect(challenge.rows.single[0], 'users');
        expect(challenge.rows.single[1], 'someone@example.com');

        // The new table exists and is usable.
        final exists = await db.execute(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          ['_oauth_identities'],
        );
        expect(exists.rows, isNotEmpty);

        await db.execute(
          'INSERT INTO "_oauth_identities" '
          '("id", "table", "user_id", "provider", "subject", "email", '
          '"created_at", "last_login_at") '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          ['oid_1', 'users', 'user_1', 'google', 'sub_123', null, 0, 0],
        );

        final identity = await db.execute(
          'SELECT "provider", "subject" FROM "_oauth_identities" WHERE "id" = ?',
          ['oid_1'],
        );
        expect(identity.rows, hasLength(1));
        expect(identity.rows.single[0], 'google');
        expect(identity.rows.single[1], 'sub_123');

        // Duplicate (table, provider, subject) is rejected.
        await expectLater(
          db.execute(
            'INSERT INTO "_oauth_identities" '
            '("id", "table", "user_id", "provider", "subject", "email", '
            '"created_at", "last_login_at") '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            ['oid_2', 'users', 'user_2', 'google', 'sub_123', null, 0, 0],
          ),
          throwsA(anything),
        );
      },
    );
  });
}
