import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/process.dart' as domain;
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// The conditional rewrite at the end of `_cleanup_logs`.
///
/// Deleting log rows only moves their pages to a freelist -- the file does
/// not shrink, so a deployment watching `df` sees retention run nightly and
/// the number never move. This is the half that hands the space back, and the
/// gate that decides whether doing so is worth it and possible.
void main() {
  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  late io.Directory projectRoot;
  late Settings settings;
  late _CapturingSink sink;

  setUp(() async {
    projectRoot = await io.Directory.systemTemp.createTemp('zonai_reclaim_');
    io.File('${projectRoot.path}/zonai.yaml').writeAsStringSync('name: test\n');
    io.Directory(
      '${projectRoot.path}/.zonai/migrations',
    ).createSync(recursive: true);
    settings = await runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
    sink = _CapturingSink();
  });

  tearDown(() async {
    if (projectRoot.existsSync()) projectRoot.deleteSync(recursive: true);
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
          stdout: io.IOSink(sink),
          stderr: io.IOSink(sink),
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

  /// Writes [total] log rows of ~4 KB each and deletes all but the newest
  /// [keep] -- the state a retention sweep leaves behind.
  ///
  /// [keep] is what makes the two gates independent, and getting it wrong is
  /// how this test first passed for the wrong reason. The freelist decides
  /// whether a rewrite is *worth* it; the surviving rows decide how much room
  /// it *needs*, because `VACUUM` copies the live pages and drops the dead
  /// ones. Deleting everything leaves nearly nothing to copy, so no plausible
  /// disk is too small for it.
  Future<void> fillAndPurge(
    ZonaiDb zonaiDb, {
    required int total,
    required int keep,
  }) async {
    final db = await zonaiDb.open();
    final padding = 'x' * 4000;
    for (var i = 0; i < total; i++) {
      await db.execute(
        'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
        '"trace_id") VALUES (?, ?, ?, ?, ?)',
        ['id$i', 'info', padding, i, 't'],
      );
    }
    await db.execute('DELETE FROM "_log" WHERE "timestamp" < ?', [
      total - keep,
    ]);
  }

  test('does nothing when there is too little on the freelist to be worth a '
      'rewrite', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    await withScope(() async {
      final zonaiDb = ZonaiDb();
      try {
        await zonaiDb.open();
        final result = await zonaiDb.reclaimLogSpace();

        expect(result.vacuumed, isFalse);
        expect(
          result.skipped,
          isNull,
          reason:
              'nothing to reclaim is not a problem, and reporting it as one '
              'would train an operator to ignore the message that matters',
        );
        expect(result.reclaimedBytes, 0);
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'rewrites the log database once enough of it is dead space, and the file '
    'actually shrinks',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          await fillAndPurge(zonaiDb, total: 5000, keep: 0);

          final logFile = io.File(settings.zonaiLogSqlitePath);
          final before = logFile.lengthSync();
          expect(before, greaterThan(16 * 1024 * 1024));

          final result = await zonaiDb.reclaimLogSpace();

          expect(result.vacuumed, isTrue);
          expect(result.skipped, isNull);
          expect(
            logFile.lengthSync(),
            lessThan(before ~/ 2),
            reason:
                'the freed pages have to leave the file, not just the '
                'table -- that difference is the entire point',
          );
          expect(result.reclaimedBytes, greaterThan(0));
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'refuses the rewrite when the volume has no room for it, and says what to '
    'do about it',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      // A volume with 1 MB free. The rewrite needs room for a copy of the
      // live pages -- ~8 MB of surviving rows below -- so this is the
      // deployment that has already filled its disk, which is exactly the one
      // where a silent skip is worst: the nightly job would report success
      // and reclaim nothing.
      final almostFull = _FakeDf(availableKilobytes: 1024);

      await withScope(processOverride: almostFull, () async {
        final zonaiDb = ZonaiDb();
        try {
          await fillAndPurge(zonaiDb, total: 8000, keep: 2000);

          final logFile = io.File(settings.zonaiLogSqlitePath);
          final before = logFile.lengthSync();

          final result = await zonaiDb.reclaimLogSpace();

          expect(result.vacuumed, isFalse);
          expect(result.skipped, isNotNull);
          expect(logFile.lengthSync(), before);

          final warning = sink.text;
          expect(warning, contains('reclaimed no disk space'));
          expect(
            warning,
            contains('Extend the volume'),
            reason:
                'at this point the database cannot fix itself -- reclaiming '
                'space needs the write that is being refused -- so the only '
                'useful message names the remedy',
          );
          expect(
            warning,
            contains(settings.zonaiLogSqlitePath),
            reason: 'an operator needs to know which volume to grow',
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('goes ahead when free space cannot be determined, rather than never '
      'reclaiming on an unrecognised platform', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    // `freeDiskBytes` returns null for anything it cannot answer. Reading
    // that as "no space" would mean a platform without a working `df` never
    // reclaims anything, forever, silently.
    final broken = _FakeDf(availableKilobytes: null);

    await withScope(processOverride: broken, () async {
      final zonaiDb = ZonaiDb();
      try {
        // The same shape as the refusal above, so the only difference
        // between them is whether the probe answered.
        await fillAndPurge(zonaiDb, total: 8000, keep: 2000);
        final result = await zonaiDb.reclaimLogSpace();
        expect(result.vacuumed, isTrue);
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// A `df` that reports a volume of the caller's choosing, or fails outright
/// when [availableKilobytes] is null.
class _FakeDf implements domain.Process {
  _FakeDf({required this.availableKilobytes});

  final int? availableKilobytes;

  @override
  Future<io.ProcessResult> run(String command, List<String> arguments) async {
    if (availableKilobytes == null) {
      return io.ProcessResult(0, 1, '', 'df: not found');
    }
    return io.ProcessResult(
      0,
      0,
      'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
          '/dev/fake 1000000 900000 $availableKilobytes 99% /data\n',
      '',
    );
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

class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}
