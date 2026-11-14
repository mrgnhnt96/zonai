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
import 'package:zonai_schema/payloads.dart';

import '../../../support/temp_directory.dart';

/// Every maintenance action that creates dead space has a reclaim path for the
/// file it dirtied.
///
/// This is the rule the incident produced, stated as a check rather than as
/// something to remember. An operator purged `_cron_jobs` — 56,483 rows — from
/// the Maintenance screen. `_cron_jobs` lives in `main`, so the delete freed
/// 9.5 MB *inside* `zonai.sqlite`, on SQLite's freelist, where `df` cannot see
/// it. Every reclaim affordance in the product was hardcoded to the log
/// database, so nothing could hand those pages back to the operating system.
///
/// The two halves were each individually defensible. `purgeTable` empties any
/// internal table; the reclaim verb rewrote one specific file. Nothing in
/// either said the sets had to line up, and the gap only became visible when
/// somebody had already made 9.5 MB they could not recover.
///
/// So the invariant is about the *relationship*, and it is the one thing
/// neither `kPurgeableTableNames` nor `kReclaimableSchemas` can state alone:
///
///   for every table a purge may empty, the database file that table lives in
///   must be a database a reclaim may target.
///
/// **Residence is asked of SQLite, not of a Dart list.** Which file a table
/// lives in is decided by `_ensureDisposableTables` moving the disposable ones
/// into their attached databases, and the app's own descriptions of that split
/// (`_disposableTableSchemas`, `_openOnce`'s `attach` map,
/// `_storageMetrics`' parallel list) are all hand-maintained. Comparing
/// against one of them would pin a copy against a copy. `sqlite_master` per
/// attached schema is the connection reporting where the tables actually are.
///
/// Related but not the same claim:
/// `reclaimable_schemas_test.dart` pins `kReclaimableSchemas` against the set
/// of databases zonai attaches. That catches a fourth database appearing. This
/// catches a purgeable *table* whose file nothing can reclaim — which is what
/// actually happened, and which would still have happened with the attached
/// set perfectly in sync.
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
    projectRoot = createCanonicalTempSync('zonai_purge_reclaim_');
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

  test('every purgeable table lives in a database a reclaim can target', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        final db = await zonaiDb.open();

        // Through `transaction` rather than `execute`: `ResqliteDelegate`
        // routes by statement verb and the writer discards row data, so a
        // `PRAGMA` sent through `execute` comes back empty. `transaction`
        // runs on the companion sqlite3 connection, and `open`'s `attach` is
        // applied to both, so that connection sees every attached database.
        final schemas = await db.transaction(
          (tx) => tx.execute('PRAGMA database_list'),
        );

        // Columns are (seq, name, file). `temp` is SQLite's scratch database,
        // not a file zonai owns.
        final attached = schemas.rows
            .map((row) => row[1]! as String)
            .where((schema) => schema != 'temp')
            .toList();

        // table -> the schemas whose sqlite_master lists it.
        final residence = <String, Set<String>>{};
        for (final schema in attached) {
          final tables = await db.transaction(
            (tx) => tx.execute(
              'SELECT "name" FROM "$schema".sqlite_master WHERE "type" = ?',
              const ['table'],
            ),
          );
          for (final row in tables.rows) {
            residence
                .putIfAbsent(row[0]! as String, () => <String>{})
                .add(schema);
          }
        }

        final unreclaimable = <String, Set<String>>{};
        final missing = <String>[];
        for (final table in kPurgeableTableNames) {
          final homes = residence[table];
          if (homes == null || homes.isEmpty) {
            // A purgeable table that does not exist after `open()` is its own
            // problem, and reporting it as "no reclaim path" would name the
            // wrong defect.
            missing.add(table);
            continue;
          }
          final orphaned = homes.difference(kReclaimableSchemas);
          if (orphaned.isNotEmpty) unreclaimable[table] = orphaned;
        }

        expect(
          missing,
          isEmpty,
          reason:
              'these purgeable tables do not exist after open(), so this test '
              'cannot say where they live — fix that before reading the '
              'reclaim half of this assertion as green',
        );

        expect(
          unreclaimable,
          isEmpty,
          reason:
              'a purge on these tables creates dead space in a database no '
              'reclaim target names, so an operator who runs it has no way to '
              'return the freed pages to the operating system — this is the '
              '_cron_jobs incident, and it is what kReclaimableSchemas exists '
              'to prevent recurring',
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

final class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
