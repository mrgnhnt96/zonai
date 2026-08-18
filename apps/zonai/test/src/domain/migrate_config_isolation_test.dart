import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/package_roots.dart';
import '../../support/temp_directory.dart';

/// Regression test: [Migrate.run] must not let an unrelated `raindrop.yaml`
/// sitting in the working directory hijack where generated Dart migrations
/// land.
///
/// `raindrop_cli`'s `--config` defaults to `./raindrop.yaml`. `Migrate.run`
/// already passes explicit `--dialect`/`--schemas`/`--out`, which override
/// that file's fields of the same name, but it never passed `--dart` — so
/// an ambient `raindrop.yaml`'s `dart:` field silently won, and its target
/// got overwritten. This bit `apps/zonai` itself: running the dev-server
/// with a cwd of `apps/zonai` (which has its own `raindrop.yaml` for its
/// internal db) clobbered the real, checked-in
/// `lib/src/internal/internal_db_migrations.dart`.
void main() {
  test(
    'ignores an unrelated raindrop.yaml in the working directory',
    () async {
      final projectRoot = createCanonicalTempSync(
        'zonai_migrate_config_isolation_',
      );
      addTearDown(() => deleteTempDirectory(projectRoot));

      final schemasDir = Directory(
        p.join(projectRoot.path, 'lib', 'src', 'schemas'),
      )..createSync(recursive: true);
      final migrationsDir = Directory(
        p.join(projectRoot.path, '.zonai', 'migrations'),
      );

      File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: migrate_config_isolation_fixture
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaPackageRootFromConfig())}
''');

      File(p.join(schemasDir.path, 'users.dart')).writeAsStringSync('''
import 'package:zonai_schema/zonai_schema.dart';

class UserSchemaRow {
  const UserSchemaRow({required this.name, this.id});

  final int? id;
  final String name;
}

class UserSchema extends Table<UserSchemaRow> {
  UserSchema(super.\$)
      : id = \$.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
        name = \$.text('name', (s) => s.name);

  @override
  UserSchemaRow fromRow(RowReader read) => UserSchemaRow(
        id: read(id),
        name: read(name),
      );

  final ColumnType<int?> id;
  final ColumnType<String> name;
}

final users = table('users', UserSchema.new);
''');

      // An unrelated raindrop.yaml, the way apps/zonai has one for its own
      // internal db. Its schemas/out/dialect are all overridden by the CLI
      // flags Migrate.run already passes; only "dart:" was left exposed.
      final sentinel = File(
        p.join(projectRoot.path, 'sentinel_migrations.dart'),
      );
      const sentinelContent =
          '// PRE-EXISTING FILE - MUST NOT BE OVERWRITTEN\n';
      sentinel.writeAsStringSync(sentinelContent);

      File(p.join(projectRoot.path, 'raindrop.yaml')).writeAsStringSync('''
dialect: sqlite
schemas: unused
out: unused
dart: sentinel_migrations.dart
''');

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      if (pubGet.exitCode != 0) {
        throw StateError(
          'dart pub get failed:\n${pubGet.stderr}\n${pubGet.stdout}',
        );
      }

      final harnessPath = p.join(
        zonaiPackageRootFromConfig(),
        'test',
        'support',
        'migrate_auto_watch_harness.dart',
      );

      final harness = await Process.start(Platform.resolvedExecutable, [
        'run',
        harnessPath,
        schemasDir.path,
        migrationsDir.path,
      ], workingDirectory: projectRoot.path);
      addTearDown(harness.kill);
      harness.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => printOnFailure('[harness stderr] $line'));

      final ready = Completer<void>();
      harness.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim() == 'READY' && !ready.isCompleted) {
              ready.complete();
            }
          });
      // 90s, not 30s: the quiet-machine readiness wait measures 10.2s, but this is a
      // process spawn plus JIT startup, so it degrades with CPU contention rather than
      // with anything about the code. At 32 busy loops on this 12-core box (load 30 ->
      // 72) a 30s budget FAILED here deterministically, while the suite passes on a
      // quiet machine and at 2.5x oversubscription. 90s matches the migration wait
      // below, which guards a comparable spawn-and-poll.
      await ready.future.timeout(const Duration(seconds: 90));

      await _waitUntil(
        () => _allMigrationSql(migrationsDir).contains('CREATE TABLE "users"'),
        reason: 'initial migration for the pre-existing schema',
        timeout: const Duration(seconds: 90),
      );

      expect(
        sentinel.readAsStringSync(),
        sentinelContent,
        reason:
            "the fixture's raindrop.yaml dart: target must be left untouched",
      );
    },
    // The outer budget is deliberately the SUM of the inner waits (90 + 90); raising one
    // without the other would leave the inner budget unreachable and decorative.
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _allMigrationSql(Directory migrationsDir) {
  if (!migrationsDir.existsSync()) return '';
  final sqlFiles = migrationsDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sql'))
      .toList();
  return sqlFiles.map((file) => file.readAsStringSync()).join('\n');
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for: $reason');
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
