import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/migrate.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../support/temp_directory.dart';

/// `migrate generate` refuses a migration that destroys data unless told it
/// may, and a refusal leaves the migrations directory exactly as it was.
///
/// raindrop_cli is replaced by a stand-in that writes what a real generate
/// writes -- a `.sql`, a `meta/NNNN_snapshot.json`, an updated journal -- so
/// the test is about the guard, not about how long an analyzer takes to start.
void main() {
  late Directory projectRoot;
  late Directory schemasDir;
  late Directory migrationsDir;
  late List<String> errors;

  Map<String, Object?> column(String name, {bool pk = false}) => {
    'name': name,
    'type': 'TEXT',
    'primaryKey': pk,
    'isNullable': !pk,
  };

  String snapshot(Map<String, List<Map<String, Object?>>> tables) =>
      jsonEncode({
        'version': '1',
        'dialect': 'sqlite',
        'id': 'x',
        'prevId': 'y',
        'indexes': <String, Object?>{},
        'foreignKeys': <String, Object?>{},
        'tables': {
          for (final MapEntry(key: name, value: columns) in tables.entries)
            name: {
              'name': name,
              'columns': {for (final c in columns) c['name']! as String: c},
            },
        },
      });

  File file(String relative) => File(p.join(migrationsDir.path, relative));

  /// A stand-in generate that produces migration 0001 with [next] as its
  /// snapshot.
  Future<int> Function(List<String>) generating(String next) => (_) async {
    file('0001_change.sql').writeAsStringSync('-- generated');
    file('meta/0001_snapshot.json').writeAsStringSync(next);
    file('meta/_journal.json').writeAsStringSync('{"entries": [0, 1]}');
    return 0;
  };

  Future<int> run(Migrate migrate, {bool allowDestructive = false}) =>
      runScoped(
        () => migrate.run(name: 'change', allowDestructive: allowDestructive),
        values: {
          settingsProvider.overrideWith(
            () => Settings(
              path: 'zonai.yml',
              migrationsPath: migrationsDir.path,
              dataPath: '.zonai/data',
              schemasPath: schemasDir.path,
              extensionsPath: '.zonai/unused/extensions',
              rulesPath: '.zonai/unused/rules',
              operationsPath: '.zonai/unused/operations',
              configPath: '.zonai/unused/config',
              emailTemplatesPath: '.zonai/unused/email_templates',
              rateLimitPath: '.zonai/unused/rate_limit',
              cronsPath: '.zonai/unused/crons',
              imagesPath: '.zonai/unused/images',
              buildSettings: BuildSettings.current(),
              version: kVersion,
            ),
          ),
          argsProvider.overrideWith(() => const Args()),
          fsProvider,
          loggerProvider.overrideWith(
            () => Logger(
              level: .error,
              stdout: CallbackSink(callback: (m) => errors.add('$m')),
              stderr: CallbackSink(callback: (m) => errors.add('$m')),
            ),
          ),
          cleanUpProvider,
        },
      );

  final id = column('id', pk: true);
  final title = column('title');

  setUp(() {
    errors = [];
    projectRoot = createCanonicalTempSync('zonai_migrate_destructive_');
    schemasDir = Directory(p.join(projectRoot.path, 'lib', 'src', 'schemas'))
      ..createSync(recursive: true);
    migrationsDir = Directory(p.join(projectRoot.path, '.zonai', 'migrations'))
      ..createSync(recursive: true);
    Directory(p.join(migrationsDir.path, 'meta')).createSync();

    file('0000_initialize.sql').writeAsStringSync('-- initial');
    file('meta/0000_snapshot.json').writeAsStringSync(
      snapshot({
        'notes': [id, title],
        'archive': [id],
      }),
    );
    file('meta/_journal.json').writeAsStringSync('{"entries": [0]}');
  });

  tearDown(() => deleteTempDirectory(projectRoot));

  Map<String, String> tree() => {
    for (final entity in migrationsDir.listSync(recursive: true))
      if (entity is File)
        p.relative(entity.path, from: migrationsDir.path): entity
            .readAsStringSync(),
  };

  test('refuses a dropped table, and writes nothing', () async {
    final before = tree();
    final migrate = Migrate()
      ..runRaindropCli = generating(
        snapshot({
          'notes': [id, title],
        }),
      );

    expect(await run(migrate), 1);
    expect(tree(), before, reason: 'a refusal must leave no partial migration');
    expect(errors.join('\n'), contains('drops table "archive"'));
    expect(errors.join('\n'), contains('--allow-destructive'));
  });

  test('refuses a dropped column', () async {
    final migrate = Migrate()
      ..runRaindropCli = generating(
        snapshot({
          'notes': [id],
          'archive': [id],
        }),
      );

    expect(await run(migrate), 1);
    expect(errors.join('\n'), contains('drops column "notes"."title"'));
    expect(file('0001_change.sql').existsSync(), isFalse);
  });

  test('keeps a destructive migration it was told to allow', () async {
    final migrate = Migrate()
      ..runRaindropCli = generating(
        snapshot({
          'notes': [id, title],
        }),
      );

    expect(await run(migrate, allowDestructive: true), 0);
    expect(file('0001_change.sql').existsSync(), isTrue);
    expect(errors, isEmpty);
  });

  test('keeps an additive migration', () async {
    final migrate = Migrate()
      ..runRaindropCli = generating(
        snapshot({
          'notes': [id, title, column('body')],
          'archive': [id],
          'tags': [id],
        }),
      );

    expect(await run(migrate), 0);
    expect(file('0001_change.sql').existsSync(), isTrue);
    expect(
      file('meta/_journal.json').readAsStringSync(),
      '{"entries": [0, 1]}',
    );
  });

  test('refuses when the new snapshot cannot be read', () async {
    final migrate = Migrate()..runRaindropCli = generating('not json');

    expect(await run(migrate), 1);
    expect(errors.join('\n'), contains('could not compare schema snapshots'));
    expect(file('0001_change.sql').existsSync(), isFalse);
  });
}
