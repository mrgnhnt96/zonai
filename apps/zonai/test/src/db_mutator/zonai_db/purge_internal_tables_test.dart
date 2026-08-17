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
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';

import '../../../support/temp_directory.dart';

/// The two locks in front of `purge`, checked against a real [ZonaiDb].
///
/// The Maintenance screen's "purge an internal table" button is gated twice:
/// the endpoint refuses a table that is not in [kPurgeableTableNames], and the
/// engine refuses one that is not in its own `_purgeableTables`. This covers
/// the engine's lock — the one that also guards the IPC path, and so the one
/// that actually has to hold.
///
/// **What this file deliberately does not test:** a purge that succeeds.
/// `_purge` reaches the operations worker to build its statement, and a bare
/// temp project has no compiled `db_operations.exe` — measured here as
/// "Operations worker is not compiled", not as a failure of the predicate.
/// Both refusals below happen *before* that dispatch, which is why they run at
/// all. The successful path is covered where it can be:
///
///  * that `NotNull('id')` names a real column on every purgeable table is
///    pinned in `zonai_schema`'s `maintenance_purgeable_tables_test.dart`,
///    against the same generated schemas the operations layer validates
///    against;
///  * that `NotNull` survives the real operations path is already true in
///    production — `_cleanup_cron_entries` purges with it on every run.
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
    projectRoot = await io.Directory.systemTemp.createTemp('zonai_purge_');
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

  /// Built directly rather than issued: this exercises the purge gates, not
  /// the auth stack.
  Jwt jwt({required bool isAdmin}) => Jwt(
    userId: UnknownId('u'),
    table: '_user',
    jwtId: JwtId('j'),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const {},
    claims: const {},
    admin: (isAdmin: isAdmin, canEdit: isAdmin ? true : null),
  );

  test(
    '_photos is refused by the engine even for an admin',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          await zonaiDb.open();

          // If `_photos` stopped being an internal table this would pass for
          // the wrong reason.
          expect(InternalDbArtifacts.tableNames, contains('_photos'));

          // Deleting a photo row also deletes the file behind it, through a
          // per-row path a bulk DELETE has no hook for. A purge would remove
          // the rows and orphan every file they pointed at, which is why
          // `_cleanup_unreferenced_photos` exists and why admin is not enough
          // to get past this.
          await expectLater(
            zonaiDb.purge(
              table: '_photos',
              where: const NotNull('id'),
              jwt: jwt(isAdmin: true),
            ),
            throwsA(isA<TableAccessDeniedException>()),
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'a non-admin is refused whatever the table',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          await zonaiDb.open();

          // The endpoint gates this too, but the engine refusing on its own is
          // what makes that a second lock rather than the only one -- a purge
          // request can also arrive over IPC from a worker process.
          await expectLater(
            zonaiDb.purge(
              table: '_log',
              where: const NotNull('id'),
              jwt: jwt(isAdmin: false),
            ),
            throwsA(isA<TableAccessDeniedException>()),
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _NullSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
