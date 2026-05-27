import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';
import 'package:zonai/src/internal/internal_db_migrate.dart';

Future<void> _ensureTestResqliteInstalled() async {
  if (isInstalled) {
    return;
  }

  final libName = defaultLibraryFileName;
  final packageRoot = Directory.current.absolute.path;
  final candidates = [
    Platform.environment['RESQLITE_LIB'],
    p.join(packageRoot, 'lib', 'gen', 'native', libName),
    p.join(packageRoot, '.dart_tool', 'lib', libName),
  ];

  for (final candidate in candidates) {
    if (candidate == null) {
      continue;
    }
    final file = File(candidate);
    if (file.existsSync()) {
      install(file.absolute.path);
      return;
    }
  }

  throw StateError(
    'Resqlite native library not found. Run scripts resqlite gen.',
  );
}

void main() {
  setUpAll(_ensureTestResqliteInstalled);

  group('InternalDbMigrate', () {
    late Directory tempDir;
    late File dbFile;
    late Raindrop db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('zonai_internal_migrate_');
      dbFile = File('${tempDir.path}/test.sqlite');
      db = Raindrop(await ResqliteDelegate.open(dbFile.path));
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('renames legacy collection columns before applying migrations', () async {
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
      expect(
        columns.rows.map((row) => row[0]).toList(),
        contains('table'),
      );
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
    });

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
