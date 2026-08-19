/// Golden-file tests for `zonai gen client`, over the playground's own tables.
///
/// The goldens are not a copy of the output kept beside it -- they *are*
/// `apps/playground/lib/gen/zonai/**` and `apps/playground/.zonai/schema.json`,
/// committed. `apps/playground` is the only non-ignored `lib/gen` in this repo
/// (`apps/zonai`, `apps/web` and `apps/server` are gitignored at
/// `.gitignore:8`, `:9` and `:107`), which is what makes a committed baseline
/// possible here and nowhere else.
///
/// Three assertions, kept apart because they fail for different reasons and a
/// single "goldens differ" would hide which:
///
///   1. **Content.** Re-running the generator over the committed schema
///      reproduces the committed bytes exactly.
///   2. **Determinism.** Two runs agree, and column order is *declaration*
///      order -- see the snapshot index-order trap in `docs/known-issues.md`,
///      which cost real time once already.
///   3. **It compiles.** The committed output passes `dart analyze` clean
///      against the real `package:zonai_client`. A golden that is byte-stable
///      and does not compile is worthless, and this is what makes the goldens
///      a check on the *barrel* (§8.1) as well as on the emitter.
///
/// [_regenerate] says how to update them; every failure message points at it.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/gen/client_generator.dart';
import 'package:zonai/src/domain/gen/client_manifest.dart';
import 'package:zonai/src/domain/gen/client_schema_document.dart';
import 'package:zonai/src/domain/gen/client_settings.dart';
import 'package:zonai_schema/zonai_schema.dart'
    show ColumnShape, ColumnShapeKind, TableSchemaShape;

/// Printed by every content failure. A golden suite nobody can update gets
/// deleted, so the instructions live in the failure, not only in a comment.
const _regenerate = '''

To update these goldens:

  * emitter changed, schema did not -- regenerate the Dart from the committed
    .zonai/schema.json (fast, no database):

      cd apps/playground && UPDATE_GOLDENS=1 dart test test/gen_client_golden_test.dart

  * the schema changed (a table, a column, a type) -- the schema has to come
    from the live registry, so run the generator itself:

      cd apps/playground && dart run --enable-asserts ../zonai/bin/zonai.dart gen client

    then re-run this test.

Never hand-edit lib/gen/zonai/** or .zonai/schema.json: `zonai gen client
--check` compares against them, and an edited hash makes a stale client look
current.
''';

/// The `client:` block in `apps/playground/zonai.yaml`, as parsed settings.
///
/// Mirrored rather than read back through `Settings`, which wants a project
/// runtime. [_settingsMatchTheProject] is the guard that keeps the mirror
/// honest.
const _settings = ClientSettings(output: 'lib/gen/zonai');

/// The framework-internal tables the playground registers, as of the commit
/// that introduced `.zonai/schema.json` (15e33b1, where all ten were still in
/// the artifact before the filter landed).
///
/// Hard-coded on purpose. Deriving this list from the same predicate the
/// filter uses would make the absence assertion tautological -- it would pass
/// just as happily if `schemaShapes()` had stopped returning system tables
/// altogether. These names are the independent record that there was something
/// to filter. [_theFilterIsLive] is the positive control that it still does.
const _internalTables = {
  '_abusers',
  '_auth_challenges',
  '_cron_jobs',
  '_jwt',
  '_log',
  '_oauth_identities',
  '_photos',
  '_push_jobs',
  '_raindrop_migrations',
  '_rate_limit',
};

/// Column kinds `ColumnShapeKind` declares that no playground table uses.
///
/// A named gap, not a silent one. Both are covered synthetically by
/// `test/gen_client_parse_test.dart`; adding a real column of either kind to
/// the playground is what this set is waiting for. A *new* kind added to the
/// enum with no representative fails [_everyColumnKindIsAccountedFor] rather
/// than slipping through, which is the point of asserting the set instead of
/// documenting it.
const _kindsWithNoPlaygroundColumn = {
  ColumnShapeKind.photos,
  ColumnShapeKind.deviceToken,
};

void main() {
  final root = _workspaceRoot();
  final playground = p.join(root, 'apps', 'playground');
  final outputDirectory = p.join(playground, 'lib', 'gen', 'zonai');
  final schemaFilePath = p.join(playground, '.zonai', 'schema.json');

  final committedSchemaBytes = File(schemaFilePath).readAsStringSync();
  final committed = ClientSchemaDocument.tryParse(committedSchemaBytes);

  // Not `expect`: everything below dereferences it, and a null here means the
  // committed artifact is unparseable, which is worth saying once and plainly.
  if (committed == null) {
    throw StateError(
      'Could not parse $schemaFilePath as a schema.json this generator '
      'understands.$_regenerate',
    );
  }

  ClientGenerator generatorFor(ClientSettings settings) => ClientGenerator(
    settings: settings,
    outputDirectory: outputDirectory,
    schemaFilePath: schemaFilePath,
    generatorVersion: kVersion,
  );

  // The real pipeline, entered one step downstream of the database: the
  // command calls `plan(await zonaiDB.schemaShapes())`, this calls it with the
  // shapes the committed schema.json holds. `fromShapes` is idempotent over an
  // already-filtered map, which `reproduces .zonai/schema.json byte for byte`
  // is what proves -- so the two entry points cannot diverge without a golden
  // moving.
  ClientGenerationPlan planOf([ClientSettings settings = _settings]) =>
      generatorFor(settings).plan(committed.tables);

  final plan = planOf();

  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    _write(plan, schemaFilePath, outputDirectory);
  }

  group('content -- the committed output is what the generator produces', () {
    test('reproduces .zonai/schema.json byte for byte', () {
      // Byte comparison, not a hash comparison. `fromJson` *recomputes* the
      // hash rather than trusting the file, so a hand-edited `hash` field
      // would compare equal on every hash assertion in this file and only
      // show up here.
      expect(
        plan.schemaFileContents,
        committedSchemaBytes,
        reason: '.zonai/schema.json is stale.$_regenerate',
      );
    });

    test('reproduces every generated file byte for byte', () {
      for (final entry in plan.files.entries) {
        final file = File(p.join(outputDirectory, entry.key));
        expect(
          file.existsSync(),
          isTrue,
          reason: '${entry.key} is missing from lib/gen/zonai.$_regenerate',
        );
        expect(
          file.readAsStringSync(),
          entry.value,
          reason: 'lib/gen/zonai/${entry.key} is stale.$_regenerate',
        );
      }
    });

    test('reproduces the manifest byte for byte', () {
      expect(
        File(
          p.join(outputDirectory, ClientManifest.fileName),
        ).readAsStringSync(),
        plan.manifest.encode(),
        reason: '${ClientManifest.fileName} is stale.$_regenerate',
      );
    });

    test('lib/gen/zonai holds exactly the manifest and nothing else', () {
      // Content comparison alone cannot see a file a *previous* generation
      // wrote and this one would not; only the directory listing can.
      final onDisk =
          Directory(outputDirectory)
              .listSync(recursive: true)
              .whereType<File>()
              // `p.relative` builds with the PLATFORM separator, and
              // `p.posix.normalize` treats a backslash as an ordinary
              // character rather than a separator -- so on Windows this read
              // 'tables\\articles.g.dart' against a manifest that records
              // 'tables/articles.g.dart', and every nested file looked like a
              // file the generator would not write. Split on the platform
              // separator, rejoin on posix, so the comparison is in the
              // manifest's own vocabulary on every OS.
              .map(
                (f) => p
                    .split(p.relative(f.path, from: outputDirectory))
                    .join('/'),
              )
              .map(p.posix.normalize)
              .where((name) => p.basename(name) != '.DS_Store')
              .toList()
            ..sort();

      expect(
        onDisk,
        [...plan.manifest.files, ClientManifest.fileName]..sort(),
        reason:
            'lib/gen/zonai holds files the generator would not write '
            'today.$_regenerate',
      );
    });

    test('the manifest, schema.json and every file agree on one hash', () {
      final manifest = ClientManifest.tryParse(
        File(
          p.join(outputDirectory, ClientManifest.fileName),
        ).readAsStringSync(),
      );

      expect(manifest, isNotNull);
      expect(manifest!.schemaHash, committed.hash);
      expect(manifest.generatorVersion, kVersion);

      for (final name in manifest.files) {
        expect(
          File(p.join(outputDirectory, name)).readAsStringSync(),
          contains('// Schema: ${committed.hash}'),
          reason: '$name was generated from a different schema.$_regenerate',
        );
      }
    });
  });

  group('determinism -- two runs produce identical bytes', () {
    test('a second plan over the same schema is byte-identical', () {
      final again = planOf();

      expect(again.schema.hash, plan.schema.hash);
      expect(again.schemaFileContents, plan.schemaFileContents);
      expect(again.manifest.encode(), plan.manifest.encode());
      expect(again.files.keys.toList(), plan.files.keys.toList());
      for (final entry in plan.files.entries) {
        expect(again.files[entry.key], entry.value, reason: entry.key);
      }
    });

    test('column order is declaration order, not alphabetical', () {
      // The trap this guards is in `docs/known-issues.md`: an older snapshot
      // generator sorted alphabetically, the current one does not, and sorting
      // reorders every generated constructor without changing a single type.
      final declared = [
        for (final column in committed.tables['posts']!.columns) column.name,
      ];
      expect(
        declared,
        [
          'id',
          'photo',
          'author_id',
          'title',
          'body',
          'created_at',
          'updated_at',
        ],
        reason: 'the schema itself no longer holds posts in declaration order',
      );

      // Sorting is a *visible* change here -- so a regression to alphabetical
      // ordering cannot pass this test by coincidence.
      expect(declared, isNot(orderedEquals([...declared]..sort())));

      final constructed = _constructorFields(
        plan.files['tables/posts.g.dart']!,
        'PostsRow',
      );
      expect(
        constructed,
        [
          'id',
          'photo',
          'authorId',
          'title',
          'body',
          'createdAt',
          'updatedAt',
          'expanded',
        ],
        reason:
            'PostsRow no longer follows the schema\'s declaration order.'
            '$_regenerate',
      );
    });

    test('tables are emitted in sorted order', () {
      // The other half of determinism: table *keys* are sorted (unlike
      // columns), so a `Map` iteration order change cannot reshuffle the
      // barrel's imports.
      expect(plan.schema.tables.keys.toList(), [
        'authors',
        'cell_edit_fixtures',
        'companies',
        'items',
        'post_summary',
        'posts',
        'users',
      ]);
      expect(
        plan.manifest.files,
        orderedEquals([...plan.manifest.files]..sort()),
      );
    });
  });

  group('the internal-table filter', () {
    test('no `_`-prefixed table reaches .zonai/schema.json', () {
      // In schema.json, not merely absent from the emitted Dart. `hash` covers
      // `tables` and nothing else and is what `--check` compares, so filtering
      // downstream of the hash would make a change to `_rate_limit` fail every
      // consumer's `--check` with no matching change to their client.
      expect(
        committed.tables.keys.where(ClientSettings.isInternalTable),
        isEmpty,
      );
      expect(
        committed.tables.keys.toSet().intersection(_internalTables),
        isEmpty,
      );
    });

    test('no `_`-prefixed table reaches the generated output', () {
      for (final entry in plan.files.entries) {
        for (final internal in _internalTables) {
          expect(
            entry.value,
            isNot(contains("'$internal'")),
            reason: '${entry.key} names the internal table $internal',
          );
        }
      }
    });

    test(_theFilterIsLive, () {
      // The positive control. Every assertion above passes just as happily if
      // `schemaShapes()` quietly stopped returning system tables, so run the
      // real filter over shapes that definitely contain one.
      final shapes = {'posts': _table('posts'), '_log': _table('_log')};

      final filtered = generatorFor(_settings).plan(shapes);
      expect(filtered.schema.tables.keys, ['posts']);
      expect(filtered.files.keys, isNot(contains('tables/_log.g.dart')));

      // ...and reversibly: `client.tables.include` is the documented way back,
      // so a filter that had become unconditional would fail here too.
      final included = generatorFor(
        const ClientSettings(output: 'lib/gen/zonai', includeTables: ['_log']),
      ).plan(shapes);
      expect(included.schema.tables.keys, ['_log', 'posts']);
      expect(included.schema.hash, isNot(filtered.schema.hash));
    });
  });

  group('coverage -- what the playground actually exercises', () {
    test('a foreign key, a nullable column, a photo and a dateTime', () {
      final posts = committed.tables['posts']!;
      final fixtures = committed.tables['cell_edit_fixtures']!;

      expect(
        posts.columns
            .firstWhere((c) => c.name == 'author_id')
            .foreignKey
            ?.table,
        'authors',
        reason: 'posts.author_id is the golden set\'s only foreign key',
      );
      expect(
        posts.columns.firstWhere((c) => c.name == 'body').isNullable,
        isTrue,
      );
      expect(
        posts.columns.firstWhere((c) => c.name == 'photo').kind,
        ColumnShapeKind.photo,
      );
      expect(
        fixtures.columns.firstWhere((c) => c.name == 'happened_at').kind,
        ColumnShapeKind.dateTime,
      );

      // ...and each one reaches the generated Dart as the type it should.
      final source = plan.files['tables/posts.g.dart']!;
      expect(source, contains('final AuthorsId authorId;'));
      expect(source, contains('final String? body;'));
      expect(source, contains('final Uri? photo;'));
      expect(
        plan.files['tables/cell_edit_fixtures.g.dart'],
        contains('final DateTime happenedAt;'),
      );
    });

    test('the view is read-only -- get, list, count and no write surface', () {
      expect(committed.tables['post_summary']!.isView, isTrue);

      final source = plan.files['tables/post_summary.g.dart']!;
      expect(_apiMethods(source, 'PostSummaryApi'), ['get', 'list', 'count']);
      expect(source, contains('a read-only view'));

      // Phase 2 has landed, so the two surfaces now differ -- which is what
      // makes the view's list meaningful. A real table carries the six
      // mutations; the view carries none of them, and the difference is
      // exactly that set.
      expect(
        _apiMethods(plan.files['tables/posts.g.dart']!, 'PostsApi'),
        containsAll(_apiMethods(source, 'PostSummaryApi')),
      );
      expect(
        _apiMethods(plan.files['tables/posts.g.dart']!, 'PostsApi').toSet()
          ..removeAll(_apiMethods(source, 'PostSummaryApi')),
        unorderedEquals(<String>[
          'create',
          'createMany',
          'update',
          'updateMany',
          'delete',
          'deleteMany',
        ]),
        reason: 'a view has nothing to write through',
      );
      expect(source, isNot(contains('PostSummaryCreate')));
      expect(source, isNot(contains('PostSummaryUpdate')));
    });

    test('secret columns never reach the client', () {
      // `_sanitizeRows` strips them from every response, so a generated field
      // would be null in every row that ever parses. Absent is the honest
      // model -- and a field named `password` on a generated row would read as
      // an API whatever its value.
      expect(
        committed.tables['users']!.columns.map((c) => c.name),
        contains('password'),
        reason: 'the assertion below is vacuous if the column is gone',
      );
      // Scoped to the ROW. A secret is unreadable, not unwritable: the server
      // special-cases it in `_requireFilterableColumn` only, which guards
      // filters. A create builder without the field cannot create a user at
      // all, so `UsersCreate.password` is correct and must not be forbidden
      // here -- what must stay absent is a field on `UsersRow` and any attempt
      // to parse one back off the wire.
      String rowOf(String file, String type) {
        final source = plan.files[file]!;
        final start = source.indexOf('final class $type {');
        return source.substring(start, source.indexOf('abstract final class'));
      }

      // The word itself appears in the row's doc, which explains the
      // omission -- so this pins the field and the constructor parameter,
      // which are the things that would actually be wrong.
      final usersRow = rowOf('tables/users.g.dart', 'UsersRow');
      expect(usersRow, isNot(contains('final String password;')));
      expect(usersRow, isNot(contains('this.password,')));
      // The note sits in the doc ABOVE the class, so it is asserted on the
      // whole file rather than on the row slice.
      expect(
        plan.files['tables/users.g.dart'],
        contains('`password` is a secret column'),
        reason: 'absent is a decision, and the model should say so',
      );
      expect(
        plan.files['tables/users.g.dart'],
        isNot(contains("_r.string(json, 'password'")),
      );
      final fixturesRow = rowOf(
        'tables/cell_edit_fixtures.g.dart',
        'CellEditFixturesRow',
      );
      expect(fixturesRow, isNot(contains('final String secretNote;')));
      expect(fixturesRow, isNot(contains('this.secretNote,')));
      expect(
        plan.files['tables/cell_edit_fixtures.g.dart'],
        isNot(contains("_r.string(json, 'secret_note'")),
      );
    });

    test(_everyColumnKindIsAccountedFor, () {
      final present = {
        for (final table in committed.tables.values)
          for (final column in table.columns) column.kind,
      };

      expect(
        ColumnShapeKind.values.toSet().difference(present),
        _kindsWithNoPlaygroundColumn,
        reason:
            'the set of column kinds with no playground representative moved. '
            'A new kind here is uncovered by these goldens -- add a column to '
            'a playground schema, or cover it synthetically the way '
            'test/gen_client_parse_test.dart covers photos and deviceToken, '
            'and update _kindsWithNoPlaygroundColumn.',
      );
    });

    test(
      'the mirrored client settings still match zonai.yaml',
      _settingsMatchTheProject(playground),
    );
  });

  group('it compiles', () {
    test('the committed output analyzes clean against package:zonai_client', () {
      // Run from inside `apps/playground`, and scoped to the generated
      // directory. Both halves are load-bearing:
      //
      //  * A root-level `dart analyze .` is SILENT here -- the root
      //    `analysis_options.yaml:9` excludes `**/lib/gen/**`. Measured
      //    2026-08-17 by appending `int _x = "s";` to the generated barrel:
      //    the root run reported nothing, so it cannot be the compile gate.
      //  * `apps/playground/analysis_options.yaml` does not `include:` the
      //    root file, it *overrides* it, and its own exclude list is only
      //    `test/fixtures/doc_scaffolds/**`. The same deliberate error run
      //    from here reported
      //    `error - zonai_client.g.dart:63:24 ... invalid_assignment`.
      //
      // (This corrects 38fd960's commit message, which says the root exclude
      // makes the test-import in `gen_client_test.dart` the only compile
      // check. Both gates work; that one is not the only one.)
      final result = Process.runSync(Platform.resolvedExecutable, const [
        'analyze',
        'lib/gen/zonai',
      ], workingDirectory: playground);

      expect(
        result.exitCode,
        0,
        reason:
            'the generated client does not analyze clean:\n'
            '${result.stdout}${result.stderr}\n'
            'If the errors name undefined types from package:zonai_client '
            '(Db, Where, OrderByTerm), the emitter is using a symbol the '
            'consumer barrel does not export -- that is a zonai_client export '
            'gap, not a golden to update. Run `dart pub get` first: an '
            'unresolved workspace reports the same symbols as undefined.',
      );
    });
  });
}

/// Method names on the generated API class, in declaration order.
List<String> _apiMethods(String source, String className) {
  final body = source.substring(source.indexOf('final class $className {'));
  return [
    for (final match in RegExp(
      r'^  Future<[^\n]*?>\s*(\w+)\s*[({]',
      multiLine: true,
    ).allMatches(body))
      match.group(1)!,
  ];
}

/// Field names in a generated row's constructor, in declaration order.
List<String> _constructorFields(String source, String className) {
  final start = source.indexOf('const $className({');
  final body = source.substring(start, source.indexOf('});', start));
  return [
    for (final match in RegExp(r'this\.(\w+)').allMatches(body))
      match.group(1)!,
  ];
}

/// Reads the `client:` block out of `zonai.yaml` without a YAML parser, and
/// asserts [_settings] still mirrors it.
///
/// A settings mirror that drifted would make every content assertion above
/// compare the generator against the wrong configuration, and they would all
/// still fail with "stale" -- pointing at the goldens rather than at this file.
dynamic Function() _settingsMatchTheProject(String playground) => () {
  final yaml = File(p.join(playground, 'zonai.yaml')).readAsStringSync();
  final block = yaml.substring(yaml.indexOf('\nclient:'));

  expect(
    RegExp(r'^\s+output:\s*(\S+)', multiLine: true).firstMatch(block)?.group(1),
    _settings.output,
  );
  for (final key in const ['tables:', 'names:', 'package:']) {
    expect(
      block,
      isNot(contains(RegExp('^\\s+$key', multiLine: true))),
      reason:
          'zonai.yaml grew a `$key` under `client:`; mirror it in _settings '
          'or these goldens are generated from the wrong configuration',
    );
  }
};

/// Writes [plan] over the committed goldens. `UPDATE_GOLDENS=1` only.
void _write(
  ClientGenerationPlan plan,
  String schemaFilePath,
  String outputDirectory,
) {
  File(schemaFilePath).writeAsStringSync(plan.schemaFileContents);
  for (final entry in plan.files.entries) {
    final file = File(p.join(outputDirectory, entry.key))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  File(
    p.join(outputDirectory, ClientManifest.fileName),
  ).writeAsStringSync(plan.manifest.encode());

  // Loud, because the run that rewrites the baseline is the one run whose
  // green means nothing.
  stderr.writeln(
    'UPDATE_GOLDENS=1: rewrote ${plan.files.length + 2} golden file(s) from '
    '.zonai/schema.json. Re-run without it, and review the diff.',
  );
}

/// A minimal shape for the filter's positive control.
TableSchemaShape _table(String name) => TableSchemaShape(
  table: name,
  columns: [
    ColumnShape(
      name: 'id',
      kind: ColumnShapeKind.id,
      isNullable: false,
      isPrimaryKey: true,
      autoIncrement: false,
      sqlType: 'TEXT',
      isSecret: false,
      foreignKey: null,
    ),
  ],
);

/// The workspace root, resolved the way `doc_snippets_test.dart` does it --
/// through `package_config.json` rather than `Directory.current`, so the test
/// is indifferent to where it was launched from.
String _workspaceRoot() {
  final configFile = File(Uri.parse(Platform.packageConfig!).toFilePath());
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

  for (final raw in config['packages'] as List<dynamic>) {
    final pkg = raw as Map<String, dynamic>;
    if (pkg['name'] != 'zonai_workspace') continue;
    return p.normalize(
      p.join(p.dirname(configFile.absolute.path), pkg['rootUri'] as String),
    );
  }

  throw StateError(
    'Package "zonai_workspace" not found in ${Platform.packageConfig}',
  );
}

const _theFilterIsLive =
    'is live -- a system table in the input is dropped, and `include` '
    'brings it back';

const _everyColumnKindIsAccountedFor =
    'every ColumnShapeKind is covered here or named as a gap';
