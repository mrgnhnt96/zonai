import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/commands/gen/client.dart';
import 'package:zonai/src/commands/gen/gen.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/domain/gen/client_emitter.dart';
import 'package:zonai/src/domain/gen/client_manifest.dart';
import 'package:zonai/src/domain/gen/dart_client_emitter.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart'
    show ColumnShape, ColumnShapeKind, TableSchemaShape;

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

ColumnShape _column(String name) => ColumnShape(
  name: name,
  kind: ColumnShapeKind.text,
  isNullable: false,
  isPrimaryKey: name == 'id',
  autoIncrement: false,
  sqlType: 'TEXT',
);

final _shapes = <String, TableSchemaShape>{
  'posts': TableSchemaShape(
    table: 'posts',
    columns: [_column('id'), _column('title')],
  ),
  'authors': TableSchemaShape(
    table: 'authors',
    columns: [_column('id'), _column('name')],
  ),
};

/// A [ZonaiDb] that answers `schemaShapes()` and nothing else -- the only
/// method `zonai gen client` calls.
class _FakeZonaiDb extends ZonaiDb {
  Map<String, TableSchemaShape> shapes = _shapes;

  @override
  Future<Map<String, TableSchemaShape>> schemaShapes() async => shapes;
}

Settings _settings(MemoryFileSystem memoryFs) {
  return runScoped(
    Settings.load,
    values: {fsProvider.overrideWith(() => memoryFs)},
  );
}

/// [ZonaiDb]'s constructor eagerly builds a `MailmanPool` per worker kind,
/// each of which reads `settings`/`fs`/`cleanUp` at construction time -- so
/// even a fake needs a scope for the moment of construction.
_FakeZonaiDb _newFakeDb(Settings settings) => runScoped(
  _FakeZonaiDb.new,
  values: {
    settingsProvider.overrideWith(() => settings),
    fsProvider.overrideWith(LocalFileSystem.new),
    cleanUpProvider,
    executableStopProvider,
  },
);

Future<({int exitCode, String output})> _run(
  MemoryFileSystem memoryFs, {
  Map<String, dynamic> flags = const {},
  _FakeZonaiDb? db,
  Future<int> Function()? command,
}) async {
  final sink = _CapturingSink();
  final settings = _settings(memoryFs);
  final fakeDb = db ?? _newFakeDb(settings);

  final exitCode = await runScoped(
    command ?? client,
    values: {
      argsProvider.overrideWith(
        () => Args(args: flags, path: ['gen', 'client']),
      ),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
      ),
      fsProvider.overrideWith(() => memoryFs),
      settingsProvider.overrideWith(() => settings),
      zonaiDbProvider.overrideWith(
        () =>
            () => fakeDb,
      ),
    },
  );

  return (exitCode: exitCode, output: sink.text);
}

MemoryFileSystem _project({String? clientBlock}) {
  final memoryFs = MemoryFileSystem();
  memoryFs.file('zonai.yaml').writeAsStringSync('''
version: 0.1.0
${clientBlock ?? ''}''');
  return memoryFs;
}

void main() {
  group('--help', () {
    test('prints usage without generating anything', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');

      final result = await _run(memoryFs, flags: {'help': true});

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai gen client'));
      expect(memoryFs.file('.zonai/schema.json').existsSync(), isFalse);
      expect(memoryFs.directory('gen/zonai').existsSync(), isFalse);
    });

    test('`zonai gen` with no subcommand prints its usage', () async {
      final memoryFs = _project();

      final result = await _run(
        memoryFs,
        flags: {'help': true},
        command: () => gen(const []),
      );

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai gen'));
    });

    test('an unknown subcommand prints usage rather than generating', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');

      final result = await _run(
        memoryFs,
        command: () => gen(const ['typescript']),
      );

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai gen'));
    });
  });

  group('configuration errors', () {
    test('no client block prints the exact block to add', () async {
      final memoryFs = _project();

      final result = await _run(memoryFs);

      expect(result.exitCode, isNot(0));
      expect(result.output, contains('client:'));
      expect(result.output, contains('output: ../app/lib/gen/zonai'));
      expect(result.output, contains('package: false'));
      expect(
        result.output,
        contains('packageName'),
        reason: 'the message is the documentation for this block',
      );
      expect(result.output, contains('exclude'));
      expect(result.output, contains('row: BlogPostsRow'));
      expect(
        result.output,
        isNot(contains('#0')),
        reason: 'a stack trace is not an answer to "how do I configure this"',
      );
      expect(memoryFs.file('.zonai/schema.json').existsSync(), isFalse);
    });

    test(
      'a client block with no output says so, and offers --output',
      () async {
        final memoryFs = _project(clientBlock: 'client:\n  package: false\n');

        final result = await _run(memoryFs);

        expect(result.exitCode, isNot(0));
        expect(result.output, contains('client.output'));
        expect(result.output, contains('--output'));
        expect(memoryFs.file('.zonai/schema.json').existsSync(), isFalse);
      },
    );

    test('--output stands in for a missing client.output', () async {
      final memoryFs = _project(clientBlock: 'client:\n  package: false\n');

      final result = await _run(memoryFs, flags: {'output': 'gen/zonai'});

      expect(result.exitCode, 0);
      expect(memoryFs.file('.zonai/schema.json').existsSync(), isTrue);
      expect(
        memoryFs
            .file('gen/zonai/${DartClientEmitter.barrelFileName}')
            .existsSync(),
        isTrue,
      );
    });

    test('--output overrides client.output', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');

      final result = await _run(memoryFs, flags: {'output': 'elsewhere'});

      expect(result.exitCode, 0);
      expect(memoryFs.directory('elsewhere').existsSync(), isTrue);
      expect(memoryFs.directory('gen/zonai').existsSync(), isFalse);
    });
  });

  group('generation', () {
    test('writes schema.json, the client and a manifest', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');

      final result = await _run(memoryFs);

      expect(result.exitCode, 0);
      expect(result.output, contains('2 table(s)'));

      final schema =
          jsonDecode(memoryFs.file('.zonai/schema.json').readAsStringSync())
              as Map<String, dynamic>;
      expect((schema['tables'] as Map).keys, ['authors', 'posts']);
      expect(schema['hash'], isA<String>());

      final generated = memoryFs
          .file('gen/zonai/${DartClientEmitter.barrelFileName}')
          .readAsStringSync();
      expect(generated, startsWith(kGeneratedClientHeader));

      final manifest = ClientManifest.tryParse(
        memoryFs
            .file('gen/zonai/${ClientManifest.fileName}')
            .readAsStringSync(),
      )!;
      expect(manifest.files, [
        'tables/authors.g.dart',
        'tables/posts.g.dart',
        DartClientEmitter.barrelFileName,
        DartClientEmitter.runtimeFileName,
      ]);
      expect(manifest.generatorVersion, kVersion);
      expect(manifest.schemaHash, schema['hash']);
    });

    test('honours tables.exclude', () async {
      final memoryFs = _project(
        clientBlock: '''
client:
  output: gen/zonai
  tables:
    exclude: [authors]
''',
      );

      await _run(memoryFs);

      final schema =
          jsonDecode(memoryFs.file('.zonai/schema.json').readAsStringSync())
              as Map<String, dynamic>;
      expect((schema['tables'] as Map).keys, ['posts']);
    });

    test(
      'warns rather than silently succeeding when nothing is left',
      () async {
        final memoryFs = _project(
          clientBlock: '''
client:
  output: gen/zonai
  tables:
    exclude: [authors, posts]
''',
        );

        final result = await _run(memoryFs);

        expect(result.output, contains('No tables to generate from'));
      },
    );
  });

  group('the write guard', () {
    test('refuses a non-empty unmanaged directory and names it', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');
      memoryFs.file('gen/zonai/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// hand written');

      final result = await _run(memoryFs);

      expect(result.exitCode, 1);
      expect(result.output, contains('gen/zonai'));
      expect(result.output, contains('app.dart'));
      expect(result.output, contains('--force'));
      expect(
        memoryFs.file('gen/zonai/app.dart').readAsStringSync(),
        '// hand written',
      );
      expect(
        memoryFs
            .file('gen/zonai/${DartClientEmitter.barrelFileName}')
            .existsSync(),
        isFalse,
      );
    });

    test('--force writes anyway, without touching what was there', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');
      memoryFs.file('gen/zonai/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// hand written');

      final result = await _run(memoryFs, flags: {'force': true});

      expect(result.exitCode, 0);
      expect(
        memoryFs.file('gen/zonai/app.dart').readAsStringSync(),
        '// hand written',
      );
      expect(
        memoryFs
            .file('gen/zonai/${DartClientEmitter.barrelFileName}')
            .existsSync(),
        isTrue,
      );
    });

    test('a second run over our own output needs no --force', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');

      expect((await _run(memoryFs)).exitCode, 0);
      expect((await _run(memoryFs)).exitCode, 0);
    });
  });

  group('--check', () {
    test('passes on matching output and writes nothing', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');
      await _run(memoryFs);

      final before = memoryFs.file('.zonai/schema.json').readAsStringSync();
      final result = await _run(memoryFs, flags: {'check': true});

      expect(result.exitCode, 0);
      expect(result.output, contains('up to date'));
      expect(memoryFs.file('.zonai/schema.json').readAsStringSync(), before);
    });

    test('fails on a drifted schema and names what differs', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');
      final settings = _settings(memoryFs);
      final db = _newFakeDb(settings);

      await _run(memoryFs, db: db);

      db.shapes = {
        ..._shapes,
        'comments': TableSchemaShape(
          table: 'comments',
          columns: [_column('id'), _column('body')],
        ),
      };

      final result = await _run(memoryFs, flags: {'check': true}, db: db);

      expect(result.exitCode, 1);
      expect(result.output, contains('stale'));
      expect(result.output, contains('.zonai/schema.json'));
      expect(result.output, contains('schema hash'));
      expect(
        result.output,
        contains('zonai gen client'),
        reason: 'the failure has to say how to fix itself',
      );
    });

    test('fails when the committed output is missing entirely', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');

      final result = await _run(memoryFs, flags: {'check': true});

      expect(result.exitCode, 1);
      expect(result.output, contains('.zonai/schema.json'));
      expect(memoryFs.directory('gen/zonai').existsSync(), isFalse);
    });

    test('fails on a hand-edited generated file', () async {
      final memoryFs = _project(clientBlock: 'client:\n  output: gen/zonai\n');
      await _run(memoryFs);

      memoryFs
          .file('gen/zonai/${DartClientEmitter.barrelFileName}')
          .writeAsStringSync('// edited');

      final result = await _run(memoryFs, flags: {'check': true});

      expect(result.exitCode, 1);
      expect(result.output, contains(DartClientEmitter.barrelFileName));
    });
  });
}
