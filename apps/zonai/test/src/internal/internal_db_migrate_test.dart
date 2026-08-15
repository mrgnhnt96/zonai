import 'dart:io';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:test/test.dart';
import 'package:zonai/src/internal/internal_db_migrate.dart';

import '../../support/temp_directory.dart';

void main() {
  setUpAll(() {
    // `defaultLibraryFileName`, not a hardcoded `.dylib`: the extension is
    // per-platform (`.so` on Linux, `resqlite.dll` on Windows), so naming the
    // macOS one meant the library was never installed off macOS and every test
    // below died in `ResqliteDelegate.open` with "native library not loaded".
    final lib = File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  group('InternalDbMigrate', () {
    late Directory tempDir;
    late File dbFile;
    late ResqliteDelegate delegate;
    late Raindrop db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'zonai_internal_migrate_',
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
      'renames legacy collection columns before applying migrations',
      () async {
        await db.execute('''
CREATE TABLE "_auth_challenges" (
  "can_consume" INTEGER NOT NULL,
  "consumed_at" INTEGER,
  "created_at" INTEGER NOT NULL,
  "expires_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "metadata" TEXT,
  "secret_hash" TEXT NOT NULL,
  "collection" TEXT NOT NULL,
  "target" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "user_id" TEXT
)''');

        await InternalDbMigrate.apply(db);

        final columns = await db.execute(
          'SELECT name FROM pragma_table_info(?) ORDER BY cid',
          ['_auth_challenges'],
        );
        expect(columns.rows.map((row) => row[0]).toList(), contains('table'));
        expect(
          columns.rows.map((row) => row[0]).toList(),
          isNot(contains('collection')),
        );

        final applied = await db.execute(
          'SELECT tag FROM "_raindrop_migrations" ORDER BY id',
        );
        expect(
          applied.rows.map((row) => row[0]).toList(),
          contains('0000_internal_initial'),
        );
      },
    );

    test('creates internal tables on a fresh database', () async {
      await InternalDbMigrate.apply(db);

      for (final table in [
        '_auth_challenges',
        '_jwt',
        '_log',
        '_photos',
        '_rate_limit',
      ]) {
        final exists = await db.execute(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table],
        );
        expect(exists.rows, isNotEmpty, reason: 'expected table $table');
      }
    });
  });
}
