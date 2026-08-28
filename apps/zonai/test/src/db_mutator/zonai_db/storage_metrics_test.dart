import 'dart:async';
import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/process.dart' as domain;
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../../support/temp_directory.dart';

/// The storage panel's collector.
///
/// What it has to get right is a distinction, not a total: a file is its live
/// pages plus its freelist, and those two halves call for opposite responses.
/// A single "3.2 GB" hides the 2.1 GB a rewrite would hand back, which is the
/// number an operator is actually looking for.
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
    projectRoot = await io.Directory.systemTemp.createTemp('zonai_storage_');
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

  Future<T> withScope<T>(
    Future<T> Function() body, {
    domain.Process? processOverride,
  }) => runMergedScopedFuture(
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
      if (processOverride != null)
        processProvider.overrideWith(() => processOverride)
      else
        processProvider,
      cleanUpProvider,
      executableStopProvider,
      migrateProvider,
    },
  );

  /// A JWT built directly rather than issued, so these tests exercise the
  /// storage collector rather than the auth stack.
  Jwt jwt({required bool isAdmin}) => Jwt(
    userId: UnknownId('u'),
    table: '_user',
    jwtId: JwtId('j'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const {},
    claims: const {},
    admin: (isAdmin: isAdmin, canEdit: isAdmin ? true : null),
  );

  test('refuses a caller who is not an admin', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await zonaiDb.open();

        // Every path, size and internal row count on the host is operator
        // information. The endpoint gates it the same way, but the engine
        // refusing on its own is what makes that gate a second lock rather
        // than the only one.
        await expectLater(
          zonaiDb.storageMetrics(jwt: jwt(isAdmin: false)),
          throwsA(isA<TableAccessDeniedException>()),
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'measures every database file zonai owns, against a real database',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          await zonaiDb.open();

          final metrics = await zonaiDb.storageMetrics(jwt: jwt(isAdmin: true));

          expect(metrics.databases.map((d) => d.name), [
            'zonai.sqlite',
            'zonai_log.sqlite',
            'zonai_rate_limit.sqlite',
          ], reason: 'application database first, matching zonaiSqlitePaths');

          for (final db in metrics.databases) {
            expect(
              db.sizeBytes,
              greaterThan(0),
              reason: '${db.name} is open, so it exists and has pages',
            );
            expect(
              db.reclaimableBytes,
              isNotNull,
              reason:
                  'the pragmas are readable on an attached schema -- a null here '
                  'would mean the storage panel silently shows "unknown" for a '
                  'file it can actually measure',
            );
            // Against the file *plus its WAL*, not the file alone.
            // `freelist_count` describes the logical database, and on a database
            // this new almost all of it is still in the uncheckpointed WAL --
            // measured here as a 4 KB main file next to a 288 KB sidecar, with
            // 28 KB on the freelist. Comparing against `sizeBytes` alone reads
            // as a bug in the collector and is not one.
            expect(
              db.reclaimableBytes,
              lessThanOrEqualTo(db.sizeBytes + db.walBytes),
            );
          }

          expect(
            metrics.totalDatabaseBytes,
            greaterThanOrEqualTo(
              metrics.databases.fold<int>(0, (sum, d) => sum + d.sizeBytes),
            ),
            reason: 'the total counts the WAL sidecars too',
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'separates reclaimable bytes from the total once rows are deleted',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          final db = await zonaiDb.open();
          final padding = 'x' * 4000;
          for (var i = 0; i < 5000; i++) {
            await db.execute(
              'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
              '"trace_id") VALUES (?, ?, ?, ?, ?)',
              ['id$i', 'info', padding, i, 't'],
            );
          }
          await db.execute('DELETE FROM "_log"', const []);

          final metrics = await zonaiDb.storageMetrics(jwt: jwt(isAdmin: true));
          final log = metrics.databases.firstWhere(
            (d) => d.name == 'zonai_log.sqlite',
          );

          // The deletion moved pages to the freelist; it did not shrink the
          // file. That gap is the entire reason this screen reports two numbers.
          expect(log.sizeBytes, greaterThan(16 * 1024 * 1024));
          expect(
            log.reclaimableBytes,
            isNotNull,
            reason: 'unknown here would hide the dead space entirely',
          );
          expect(
            log.reclaimableBytes!,
            greaterThan(log.sizeBytes ~/ 2),
            reason:
                'most of the file is dead after deleting every row, and a UI '
                'showing only the total would report it as space in use',
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'counts every internal table, including the ones the dashboard hides',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          final db = await zonaiDb.open();
          for (var i = 0; i < 3; i++) {
            await db.execute(
              'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
              '"trace_id") VALUES (?, ?, ?, ?, ?)',
              ['id$i', 'info', 'hello', i, 't'],
            );
          }

          final metrics = await zonaiDb.storageMetrics(jwt: jwt(isAdmin: true));

          expect(
            metrics.tables.map((t) => t.table).toSet(),
            InternalDbArtifacts.tableNames,
            reason:
                'the dashboard filters _-prefixed tables out, which is why _log '
                'reaching 4.6M rows was invisible until the disk was gone -- '
                'this screen is where that becomes visible',
          );
          expect(
            metrics.tables.firstWhere((t) => t.table == '_log').rowCount,
            3,
            reason:
                '_log lives in an attached file and still has to be counted',
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('reports free disk space as unknown rather than zero when df cannot be '
      'read', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    // `freeDiskBytes` answers null for anything it cannot determine. Passing
    // that through as null is what lets the UI say "unknown"; collapsing it to
    // 0 here would report a full disk on every platform whose `df` we cannot
    // parse -- the opposite situation, and the one that sends an operator
    // hunting for space that was never missing.
    await withScope(processOverride: _BrokenDf(), () async {
      final zonaiDb = ZonaiDb();
      try {
        await zonaiDb.open();

        final metrics = await zonaiDb.storageMetrics(jwt: jwt(isAdmin: true));

        expect(metrics.freeDiskBytes, isNull);
        expect(
          metrics.freeDiskBytes,
          isNot(0),
          reason: 'unknown and full are opposite answers, not the same one',
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('survives a project that has never stored a photo', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await zonaiDb.open();
        expect(io.Directory(settings.imagesPath).existsSync(), isFalse);

        final metrics = await zonaiDb.storageMetrics(jwt: jwt(isAdmin: true));

        // A missing images directory is the normal state of a deployment that
        // has not accepted an upload, not a fault to report.
        expect(metrics.photosBytes, 0);
        expect(metrics.photosFileCount, 0);
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('reports an absolute path even when the project configures a relative '
      'one', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    // The case every other test here misses, and the reason this one exists:
    // they all call `Settings.load(projectRoot.path)` with an absolute temp
    // directory, so the paths are already absolute before the collector sees
    // them and an assertion on absoluteness passes without proving anything.
    //
    // Production is the opposite. `Settings.load()` takes no basePath, joins
    // onto null, and hands the collector `.zonai/data/zonai.sqlite`. Observed
    // live on the dev server as `../playground/.zonai/data/zonai.sqlite` --
    // resolvable only against the server's working directory, which is
    // precisely what the operator reading the field does not have.
    final originalCwd = io.Directory.current;
    try {
      io.Directory.current = projectRoot;

      final relativeSettings = await runMergedScopedFuture(
        () async => Settings.load(),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );
      await runMergedScopedFuture(
        () async {
          // Checked inside the scope, because reading the paths needs `fs`.
          expect(
            relativeSettings.zonaiSqlitePaths.every(p.isRelative),
            isTrue,
            reason:
                'the premise of this test: settings loaded without a basePath '
                'are relative, so the collector really is handed a relative '
                'path. If this ever fails the test below proves nothing.',
          );

          final zonaiDb = ZonaiDb();
          try {
            await zonaiDb.open();
            final metrics = await zonaiDb.storageMetrics(
              jwt: jwt(isAdmin: true),
            );

            for (final db in metrics.databases) {
              expect(
                p.isAbsolute(db.path),
                isTrue,
                reason:
                    '${db.name} arrived as "${db.path}"; a relative path '
                    'resolves against the reader\'s cwd, not the server\'s',
              );
              expect(
                p.basename(db.path),
                db.name,
                reason: 'absolutising must not change which file is described',
              );
            }
          } finally {
            await zonaiDb.dispose();
          }
        },
        override: {
          fsProvider.overrideWith(LocalFileSystem.new),
          loggerProvider.overrideWith(
            () => Logger(
              level: .warning,
              stdout: io.IOSink(_NullSink()),
              stderr: io.IOSink(_NullSink()),
            ),
          ),
          settingsProvider.overrideWith(() => relativeSettings),
          processProvider,
          cleanUpProvider,
          executableStopProvider,
          migrateProvider,
        },
      );
    } finally {
      io.Directory.current = originalCwd;
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Swallows log output; these tests assert on returned values, not on logs.
class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}

/// A `df` that fails, so free space cannot be determined.
class _BrokenDf implements domain.Process {
  @override
  Future<io.ProcessResult> run(String command, List<String> arguments) async {
    return io.ProcessResult(0, 1, '', '$command: not found');
  }

  @override
  Future<io.ProcessResult> runDart(List<String> arguments) =>
      throw UnimplementedError();

  @override
  Future<io.Process> start(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) => throw UnimplementedError();

  @override
  bool kill(int pid) => throw UnimplementedError();
}
