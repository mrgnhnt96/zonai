/// A second generated client, for a schema that exists only to make the docs
/// checkable.
///
/// `/dart-client/typed-client` teaches with `books`, `articles`, `notes` and
/// `users` because the prose reads better with a shelf of books than with
/// `cell_edit_fixtures`. Those tables are not in the playground, so every fence
/// calling them was `no-analyze` -- trusted rather than checked, which is the
/// exact failure this campaign exists to end.
///
/// The fix is a fixture client, and the rule that comes with it: a second
/// generated artifact in the repo has to be kept honest the same way the
/// playground's is, or it silently rots the first time the emitter changes.
///
/// WHERE THE SOURCE OF TRUTH IS, and why it is not a zonai project.
/// [_shapes] below IS the fixture. There is no fixture app, no database and no
/// migration: the generator's real entry point downstream of the database takes
/// `Map<String, TableSchemaShape>`, so shapes authored here reach exactly the
/// code path `zonai gen client` reaches. A whole project would add a build to
/// maintain and would not exercise one additional line.
///
/// `schema.json` and the Dart under `lib/gen/doc_fixture/` are OUTPUTS.
/// Never hand-edit either: the hash is recomputed from the shapes rather than
/// read from the file, so an edited artifact fails here and nowhere else.
///
/// To update, after changing [_shapes] or the emitter:
///
///   cd apps/playground && UPDATE_GOLDENS=1 dart test test/doc_fixture_client_golden_test.dart
///
/// then re-run without it and review the diff.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zonai/src/domain/gen/client_generator.dart';
import 'package:zonai/src/domain/gen/client_manifest.dart';
import 'package:zonai/src/domain/gen/client_schema_document.dart';
import 'package:zonai/src/domain/gen/client_settings.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai_schema/zonai_schema.dart'
    show ColumnShape, ColumnShapeKind, ForeignKeyShape, TableSchemaShape;

const _output = 'lib/gen/doc_fixture';
const _settings = ClientSettings(output: _output);

ColumnShape _id(String name, {String? references}) => ColumnShape(
  name: name,
  kind: ColumnShapeKind.id,
  isNullable: false,
  isPrimaryKey: references == null,
  autoIncrement: false,
  sqlType: 'TEXT',
  foreignKey: references == null
      ? null
      : ForeignKeyShape(table: references, column: 'id'),
);

ColumnShape _col(
  String name,
  ColumnShapeKind kind, {
  String sqlType = 'TEXT',
  bool isNullable = false,
  List<String> enumValues = const [],
}) => ColumnShape(
  name: name,
  kind: kind,
  isNullable: isNullable,
  isPrimaryKey: false,
  autoIncrement: false,
  sqlType: sqlType,
  enumValues: enumValues,
);

/// THE FIXTURE. Every column here exists because a specific fence needs it --
/// if a column has no fence, it should not be here, and if a fence has no
/// column it stays `no-analyze`.
///
///   books.shelf      an enum column: `Books.shelf.eq(BooksShelf.finished)`,
///                    `book.shelf.value`, `.isKnown`, and `== 'reading'`
///   books.tags       `$.enumList` becoming `List<BooksTags>`
///   books.owner_id   the second hop of `Notes.expand.bookId.ownerId`
///   articles.view_count  `NumField.increment()`
///   articles.tags    `ListField.add('dart')` -- a plain `list`, not an enumList
///   notes.book_id    the first hop of the expand chain
///   users.settings   `MapField.at(const ['theme'], 'dark')`
final _shapes = <String, TableSchemaShape>{
  'articles': TableSchemaShape(
    table: 'articles',
    columns: [
      _id('id'),
      _col('title', ColumnShapeKind.text),
      _col('view_count', ColumnShapeKind.integer, sqlType: 'INTEGER'),
      _col('tags', ColumnShapeKind.list),
    ],
  ),
  'books': TableSchemaShape(
    table: 'books',
    columns: [
      _id('id'),
      _col('title', ColumnShapeKind.text),
      _col(
        'shelf',
        ColumnShapeKind.enum_,
        enumValues: const ['wantToRead', 'reading', 'finished'],
      ),
      _col(
        'tags',
        ColumnShapeKind.enumList,
        enumValues: const ['fiction', 'reference', 'borrowed'],
      ),
      _id('owner_id', references: 'users'),
    ],
  ),
  'notes': TableSchemaShape(
    table: 'notes',
    columns: [
      _id('id'),
      _col('body', ColumnShapeKind.text),
      _id('book_id', references: 'books'),
    ],
  ),
  'users': TableSchemaShape(
    table: 'users',
    columns: [
      _id('id'),
      _col('name', ColumnShapeKind.text),
      _col('settings', ColumnShapeKind.map),
    ],
  ),
};

void main() {
  final root = _workspaceRoot();
  final playground = p.join(root, 'apps', 'playground');
  final outputDirectory = p.join(playground, p.joinAll(p.posix.split(_output)));
  final schemaFilePath = p.join(outputDirectory, 'schema.json');

  final plan = ClientGenerator(
    settings: _settings,
    outputDirectory: outputDirectory,
    schemaFilePath: schemaFilePath,
    generatorVersion: kVersion,
  ).plan(_shapes);

  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    _write(plan, schemaFilePath, outputDirectory);
  }

  group('the committed fixture client is what the generator produces', () {
    test('reproduces schema.json byte for byte', () {
      // Byte comparison rather than hash comparison, for the same reason the
      // playground's golden does it this way: `fromJson` RECOMPUTES the hash
      // instead of trusting the file, so a hand-edited artifact compares equal
      // on every hash assertion and shows up only here.
      expect(
        File(schemaFilePath).readAsStringSync(),
        plan.schemaFileContents,
        reason: 'schema.json is stale -- see this file\'s header',
      );
    });

    test('reproduces every generated file byte for byte', () {
      for (final entry in plan.files.entries) {
        final file = File(p.join(outputDirectory, entry.key));
        expect(
          file.existsSync(),
          isTrue,
          reason: '${entry.key} is missing -- see this file\'s header',
        );
        expect(
          file.readAsStringSync(),
          entry.value,
          reason: '${entry.key} is stale -- see this file\'s header',
        );
      }
    });

    test('reproduces the manifest byte for byte', () {
      // The manifest is written OUTSIDE `plan.files`, so the loop above never
      // looks at it -- a stale hash or a dropped entry survives every other
      // assertion here.
      expect(
        File(
          p.join(outputDirectory, ClientManifest.fileName),
        ).readAsStringSync(),
        plan.manifest.encode(),
        reason:
            '${ClientManifest.fileName} is stale -- see this file\'s header',
      );
    });

    test('$_output holds exactly what the generator would write', () {
      // Content comparison alone cannot see a file a *previous* generation
      // wrote and this one would not; only the directory listing can. Unlike
      // the playground's client, this fixture keeps `schema.json` inside the
      // output directory, so it is expected here too.
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
        [...plan.manifest.files, ClientManifest.fileName, 'schema.json']
          ..sort(),
        reason:
            '$_output holds files the generator would not write today '
            '-- see this file\'s header',
      );
    });

    test(
      'the committed schema.json parses as one this generator understands',
      () {
        final parsed = ClientSchemaDocument.tryParse(
          File(schemaFilePath).readAsStringSync(),
        );
        expect(parsed, isNotNull);
        expect(parsed!.tables.keys, unorderedEquals(_shapes.keys));
      },
    );
  });

  group('the fixture carries what the docs actually call', () {
    // These are not decoration. Each one pins a column that a specific fence on
    // /dart-client/typed-client depends on, so deleting the column fails HERE
    // with a reason rather than in an analyzer error inside a doc scaffold.
    test('books.shelf is an enum column with the members the prose names', () {
      final shelf = _shapes['books']!.columns.firstWhere(
        (c) => c.name == 'shelf',
      );
      expect(shelf.kind, ColumnShapeKind.enum_);
      expect(shelf.enumValues, containsAll(['reading', 'finished']));
    });

    test('the expand chain notes -> books -> users is two hops deep', () {
      final bookId = _shapes['notes']!.columns.firstWhere(
        (c) => c.name == 'book_id',
      );
      final ownerId = _shapes['books']!.columns.firstWhere(
        (c) => c.name == 'owner_id',
      );
      expect(bookId.foreignKey?.table, 'books');
      expect(ownerId.foreignKey?.table, 'users');
    });

    test('articles has a numeric counter and a plain list', () {
      final columns = {for (final c in _shapes['articles']!.columns) c.name: c};
      expect(columns['view_count']!.kind, ColumnShapeKind.integer);
      expect(
        columns['tags']!.kind,
        ColumnShapeKind.list,
        reason: 'ListField.add takes an element; enumList would type it',
      );
    });

    test('users.settings is a map column, which is what MapField.at needs', () {
      final settings = _shapes['users']!.columns.firstWhere(
        (c) => c.name == 'settings',
      );
      expect(settings.kind, ColumnShapeKind.map);
    });
  });
}

void _write(
  ClientGenerationPlan plan,
  String schemaFilePath,
  String outputDirectory,
) {
  File(schemaFilePath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(plan.schemaFileContents);
  for (final entry in plan.files.entries) {
    File(p.join(outputDirectory, entry.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  File(
    p.join(outputDirectory, ClientManifest.fileName),
  ).writeAsStringSync(plan.manifest.encode());

  stderr.writeln(
    'UPDATE_GOLDENS=1: rewrote ${plan.files.length + 2} fixture file(s). '
    'Re-run without it, and review the diff.',
  );
}

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
