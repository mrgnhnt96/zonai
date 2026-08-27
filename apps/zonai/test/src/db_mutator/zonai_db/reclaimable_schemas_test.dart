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

/// The app-side half of the `kReclaimableSchemas` drift pin.
///
/// `kReclaimableSchemas` is written out by hand in
/// `libs/zonai_schema/lib/src/payloads/maintenance_actions.dart` rather than
/// derived, because `payloads.dart` is the library `apps/web` compiles to
/// JavaScript and the engine's constants sit behind an import chain that
/// reaches native SQLite. Writing a set out costs drift, so drift is what has
/// to be pinned — and it takes two tests, on opposite sides of the dependency
/// arrow, because neither side can see both halves.
///
/// **The other half is
/// `libs/zonai_schema/test/src/payloads/maintenance_reclaimable_schemas_test.dart`.**
/// That one runs inside `zonai_schema`, which cannot import `apps/zonai`, so
/// it can only pin the constant against literals: the three spellings, that
/// `main` and `logdb` are members, and that no member looks like a path. It
/// catches an edit *to the constant* and nothing about the engine.
///
/// This half is the reverse. `apps/zonai` depends on `zonai_schema`, so it can
/// see both sides, and it pins the constant against what the engine actually
/// does rather than against a second transcription of the same three strings.
/// It catches an edit *to the engine* that the constant did not follow. It
/// says nothing about the shape of the members — that stays over there.
///
/// Neither half is sufficient and each names the other, because a one-way
/// reference is how a pair like this drifts apart.
///
/// The two failures worth catching, one per test below:
///
///  - a fourth database is attached in `_openOnce` and the reclaim picker
///    silently cannot target it, so operators have no way to hand its dead
///    pages back to the OS;
///  - one of the three is renamed on the engine side, so the browser keeps
///    sending an identifier the server's allowlist now rejects.
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
    projectRoot = createCanonicalTempSync('zonai_reclaimable_schemas_');
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

  test(
    'kReclaimableSchemas is exactly the set of databases zonai opens',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          final db = await zonaiDb.open();

          // SQLite's own answer, not a re-reading of any Dart list. The
          // three candidate authorities in the app -- `_openOnce`'s `attach`
          // map, `_storageMetrics`' parallel `schemas` list, and
          // `_schemaFile`'s switch -- are all themselves hand-maintained, so
          // comparing against one of them would only pin a copy against a
          // copy. `PRAGMA database_list` is the connection reporting what it
          // is actually holding open, which is the thing a reclaim target
          // has to name.
          //
          // Through `transaction` rather than `execute` for the reason
          // `_ReclaimSpaceX._reclaimPragmaInt` documents: `ResqliteDelegate`
          // routes by statement verb, `PRAGMA` is not a read verb, and the
          // writer discards row data. `transaction` runs on the companion
          // sqlite3 connection, which returns rows -- and `open`'s `attach`
          // is applied to BOTH connections, so that connection sees every
          // attached database.
          final result = await db.transaction(
            (tx) => tx.execute('PRAGMA database_list'),
          );

          // Columns are (seq, name, file). `temp` is SQLite's scratch
          // database rather than a file zonai owns; it is listed only once
          // something has forced it into existence, so excluding it keeps
          // this test from depending on whether anything in `open()`
          // happened to create a temp table.
          final attached = result.rows
              .map((row) => row[1]! as String)
              .where((schema) => schema != 'temp')
              .toSet();

          expect(
            attached,
            equals(kReclaimableSchemas),
            reason:
                'every database the engine holds open must be reclaimable, '
                'and nothing else may be offered as a target',
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the engine accepts every member as a reclaim target', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await zonaiDb.open();

        for (final schema in kReclaimableSchemas) {
          // `ZonaiDb.reclaimSpace` resolves the target through
          // `_ReclaimSpaceX._schemaFile` before entering the write queue,
          // and an unknown name throws `ArgumentError` there rather than
          // rewriting the wrong file. So this drives the server-side
          // allowlist with exactly the strings a browser is entitled to
          // send: if `kLogDbSchema` were renamed and the payload constant
          // did not follow, this is the throw the operator would get.
          //
          // The floor is set absurdly high so every call takes the
          // "not worth it" branch and no test rewrites a database file.
          final result = await zonaiDb.reclaimSpace(
            schema: schema,
            minReclaimableBytes: 1 << 40,
          );

          expect(result.target, schema);
          expect(
            result.vacuumed,
            isFalse,
            reason: 'a 1 TiB floor must not be met by a fresh database',
          );
        }
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a schema outside the set is refused rather than guessed at', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await zonaiDb.open();

        // The other direction of the same allowlist: the engine must not
        // be *wider* than `kReclaimableSchemas`. `VACUUM` rewrites a file,
        // and the target arrives from a browser, so a name the engine does
        // not recognise has to stop here.
        await expectLater(
          zonaiDb.reclaimSpace(
            schema: 'photosdb',
            minReclaimableBytes: 1 << 40,
          ),
          throwsA(isA<ArgumentError>()),
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
