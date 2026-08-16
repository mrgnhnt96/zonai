import 'dart:convert';
import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../../support/package_roots.dart';
import '../../../support/temp_directory.dart';

/// `_cleanup_unreferenced_photos` used to decide what to delete by reading
/// everything first: every `_photos` row, and every row *and every column* of
/// every collection carrying a photo column. Same shape as the `_cleanup_logs`
/// defect fixed in `df76021`, in a cron that ships — and it had no test at all,
/// which is why the shape survived the fix to its sibling.
///
/// WHAT THESE TESTS DO AND DO NOT PROVE — read this before trusting them.
///
/// They do **not** fail against the unpaged version, and no behavioural test
/// could: the old code was *unbounded*, not *incorrect*. It read every row and
/// then deleted exactly the same set. Unboundedness is a memory property, and
/// asserting it needs a measurement this layer cannot take. Anyone reading a
/// green run here as proof that the paging works has read too much into it.
///
/// What they are: the first tests this cron has ever had, and a regression net
/// under the risk the rewrite introduced. Paging brings a cursor, and a cursor
/// can fail in ways the single-shot read could not — stopping after one page,
/// re-reading a page forever, or skipping rows at a boundary. Every count below
/// is therefore deliberately larger than `_photoScanPageSize` (500), so the
/// loop's boundary and its exit condition are exercised rather than assumed.
///
/// WHY THIS COMPILES A PROJECT: `_cleanupUnreferencedPhotos` calls
/// `schemaShapes()`, which asks the operations worker which collections carry
/// photo columns — user schemas are only known at runtime. That dependency is
/// not new and cannot be mocked away here, so the fixture pays for one
/// `zonai compile` (~17s, once for the file).
///
/// WHAT IS NOT COVERED HERE, said out loud rather than left to be assumed:
/// the case where a photo IS referenced and is therefore *skipped* rather than
/// deleted. That is the path the keyset cursor exists for — a skipped row is
/// still there on the next query, so a cursor that failed to advance would
/// re-read it forever. Exercising it needs a user collection with a photo
/// column and applied migrations, which is a bigger fixture than this one.
/// It belongs in the e2e layer, which already drives photos over HTTP.
void main() {
  late io.Directory projectRoot;
  late Settings settings;

  setUpAll(() async {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }

    projectRoot = createCanonicalTempSync('zonai_photo_cleanup_');

    io.Directory(
      p.join(projectRoot.path, 'lib', 'src', 'config'),
    ).createSync(recursive: true);
    // ZonaiDb.open() refuses a project with no migrations directory. There is
    // no user schema here, so an empty directory is the whole of what it needs.
    io.Directory(
      p.join(projectRoot.path, '.zonai', 'migrations'),
    ).createSync(recursive: true);

    io.File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: zonai_photo_cleanup_fixture
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaPackageRootFromConfig())}
''');

    io.File(p.join(projectRoot.path, 'zonai.yaml')).writeAsStringSync('''
version: $kVersion
configPath: lib/src/config
''');

    io.File(
      p.join(projectRoot.path, 'lib', 'src', 'config', 'app_config.dart'),
    ).writeAsStringSync('''
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'photo-cleanup-fixture',
    passwordSecret: 'test-password-secret',
    jwtSecret: 'test-jwt-secret',
  );
}
''');

    final pubGet = await io.Process.run(io.Platform.resolvedExecutable, const [
      'pub',
      'get',
    ], workingDirectory: projectRoot.path);
    if (pubGet.exitCode != 0) {
      throw StateError('dart pub get failed:\n${pubGet.stderr}');
    }

    final zonaiEntry = p.normalize(
      p.join(io.Directory.current.path, 'bin', 'zonai.dart'),
    );
    final compile = await io.Process.run(io.Platform.resolvedExecutable, [
      'run',
      zonaiEntry,
      'compile',
      '--no-version-check',
      '--no-schema-version-check',
    ], workingDirectory: projectRoot.path);
    if (compile.exitCode != 0) {
      throw StateError('zonai compile failed:\n${compile.stderr}');
    }

    settings = await runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
  });

  tearDownAll(() {
    if (projectRoot.existsSync()) deleteTempDirectory(projectRoot);
  });

  /// Each test starts from an empty `_photos` table and an empty images dir.
  setUp(() async {
    final images = io.Directory(settings.imagesPath);
    if (images.existsSync()) images.deleteSync(recursive: true);
    images.createSync(recursive: true);
  });

  Future<T> withScope<T>(Future<T> Function() body) => runMergedScopedFuture(
    body,
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

  /// Seeds [count] `_photos` rows older than the one-hour grace period, each
  /// with a real file on disk — the file being the reason this cron cannot
  /// become a bulk delete.
  ///
  /// Ids are zero-padded so lexicographic order matches insertion order, which
  /// is what a keyset cursor over `id` walks.
  Future<void> seedStalePhotos(ZonaiDb zonaiDb, {required int count}) async {
    final db = await zonaiDb.open();
    final images = io.Directory(settings.imagesPath)
      ..createSync(recursive: true);
    final stale = DateTime.now()
        .subtract(const Duration(hours: 6))
        .millisecondsSinceEpoch;

    for (var i = 0; i < count; i++) {
      final id = 'p${i.toString().padLeft(6, '0')}ph';
      final path = '$id.png';
      io.File(p.join(images.path, path)).writeAsBytesSync([0]);

      await db.execute(
        'INSERT INTO "_photos" ("id", "owner_id", "owner_collection", '
        '"table", "created_at", "path", "extension") '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, 'owner', 'widgets', 'widgets', stale, path, 'png'],
      );
    }
  }

  Future<void> clearPhotos(ZonaiDb zonaiDb) async {
    final db = await zonaiDb.open();
    await db.execute('DELETE FROM "_photos"');
  }

  Future<int> photoRowCount(ZonaiDb zonaiDb) async {
    final db = await zonaiDb.open();
    final result = await db.execute('SELECT COUNT(*) FROM "_photos"');
    return result.rows.single.first! as int;
  }

  test('deletes every unreferenced photo across more than one page', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await clearPhotos(zonaiDb);
        // 1,250 = two full pages plus a partial one, so the loop's
        // "stop when the page is short" exit is exercised, not assumed.
        await seedStalePhotos(zonaiDb, count: 1250);
        expect(await photoRowCount(zonaiDb), 1250);

        final deleted = await zonaiDb.cleanupUnreferencedPhotos();

        expect(
          deleted,
          1250,
          reason:
              'a scan that stops after one page would report 500 and leave '
              '750 behind on every run, forever',
        );
        expect(await photoRowCount(zonaiDb), 0);
      } finally {
        await zonaiDb.dispose();
      }
    });
  });

  test('deletes the files, not just the rows', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await clearPhotos(zonaiDb);
        await seedStalePhotos(zonaiDb, count: 600);
        expect(io.Directory(settings.imagesPath).listSync(), hasLength(600));

        await zonaiDb.cleanupUnreferencedPhotos();

        // This is what makes "never turn this into mutate.purge" enforceable
        // by something other than a comment. A bulk `DELETE ... WHERE` would
        // empty `_photos` and leave every file on disk — the row count would
        // look perfect and the leak would be permanent and silent.
        expect(
          io.Directory(settings.imagesPath).listSync(),
          isEmpty,
          reason:
              'deleting a _photos row must delete its file; this is exactly '
              'why _photos is excluded from mutate.purge',
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  });

  test('a photo inside the grace period survives, even mid-page', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await clearPhotos(zonaiDb);
        await seedStalePhotos(zonaiDb, count: 600);

        // Id sorts into the middle of the first page, so it is excluded by the
        // WHERE rather than by happening to fall past the end of the scan.
        final db = await zonaiDb.open();
        io.File(
          p.join(settings.imagesPath, 'p000250fresh.png'),
        ).writeAsBytesSync([0]);
        await db.execute(
          'INSERT INTO "_photos" ("id", "owner_id", "owner_collection", '
          '"table", "created_at", "path", "extension") '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            'p000250freshph',
            'owner',
            'widgets',
            'widgets',
            DateTime.now().millisecondsSinceEpoch,
            'p000250fresh.png',
            'png',
          ],
        );

        await zonaiDb.cleanupUnreferencedPhotos();

        expect(
          await photoRowCount(zonaiDb),
          1,
          reason:
              'the grace period is now a WHERE rather than a Dart check after '
              'the whole table was read — a row inside it must never be read '
              'as a candidate at all',
        );
        expect(
          io.File(p.join(settings.imagesPath, 'p000250fresh.png')).existsSync(),
          isTrue,
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  });
}
