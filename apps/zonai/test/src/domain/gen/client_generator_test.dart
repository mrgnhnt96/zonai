import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/gen/client_emitter.dart';
import 'package:zonai/src/domain/gen/client_generator.dart';
import 'package:zonai/src/domain/gen/client_manifest.dart';
import 'package:zonai/src/domain/gen/client_schema_document.dart';
import 'package:zonai/src/domain/gen/client_settings.dart';
import 'package:zonai/src/domain/gen/dart_client_emitter.dart';
import 'package:zonai_schema/zonai_schema.dart'
    show ColumnShape, ColumnShapeKind, TableSchemaShape;

const _output = 'gen/zonai';
const _schemaPath = '.zonai/schema.json';

ColumnShape _column(
  String name, {
  ColumnShapeKind kind = ColumnShapeKind.text,
}) {
  return ColumnShape(
    name: name,
    kind: kind,
    isNullable: false,
    isPrimaryKey: name == 'id',
    autoIncrement: false,
    sqlType: 'TEXT',
  );
}

/// Column order here is *declaration* order, not alphabetical -- the property
/// the generator has to preserve.
final _shapes = <String, TableSchemaShape>{
  'posts': TableSchemaShape(
    table: 'posts',
    columns: [_column('id'), _column('title'), _column('author_id')],
  ),
  'authors': TableSchemaShape(
    table: 'authors',
    columns: [_column('id'), _column('name')],
  ),
  'audit_log': TableSchemaShape(
    table: 'audit_log',
    columns: [_column('id'), _column('action')],
  ),
};

ClientGenerator _generator({
  ClientSettings? settings,
  ClientEmitter emitter = const DartClientEmitter(),
}) {
  return ClientGenerator(
    settings: settings ?? const ClientSettings(output: _output),
    outputDirectory: _output,
    schemaFilePath: _schemaPath,
    generatorVersion: '9.9.9',
    emitter: emitter,
  );
}

T _scoped<T>(FileSystem memoryFs, T Function() body) {
  return runScoped(body, values: {fsProvider.overrideWith(() => memoryFs)});
}

/// An emitter whose file set the test controls, for the stale-removal cases.
final class _FixedEmitter implements ClientEmitter {
  const _FixedEmitter(this.files);

  final Map<String, String> files;

  @override
  Map<String, String> emit(ClientGenerationInput input) => files;
}

void main() {
  group('schema.json', () {
    test('two runs are byte-identical', () {
      final first = _generator().plan(_shapes);
      final second = _generator().plan(_shapes);

      expect(second.schemaFileContents, first.schemaFileContents);
      expect(second.schema.hash, first.schema.hash);
      expect(second.files, first.files);
    });

    test('is insensitive to the order the shapes arrive in', () {
      final reversed = <String, TableSchemaShape>{
        for (final key in _shapes.keys.toList().reversed) key: _shapes[key]!,
      };

      expect(
        _generator().plan(reversed).schemaFileContents,
        _generator().plan(_shapes).schemaFileContents,
      );
    });

    test('sorts table keys but never column order', () {
      final plan = _generator().plan(_shapes);
      final json = jsonDecode(plan.schemaFileContents) as Map<String, dynamic>;
      final tables = json['tables'] as Map<String, dynamic>;

      expect(tables.keys, ['audit_log', 'authors', 'posts']);

      final posts = tables['posts'] as Map<String, dynamic>;
      final columns = [
        for (final column in posts['columns'] as List)
          (column as Map<String, dynamic>)['name'],
      ];
      expect(
        columns,
        ['id', 'title', 'author_id'],
        reason:
            'column order is declaration order; sorting it would reorder '
            'every generated constructor',
      );
    });

    test('excluded tables are absent, and change the hash', () {
      final all = _generator().plan(_shapes);
      final some = _generator(
        settings: const ClientSettings(
          output: _output,
          excludeTables: ['audit_log'],
        ),
      ).plan(_shapes);

      expect(some.schema.tables.keys, ['authors', 'posts']);
      expect(some.schema.hash, isNot(all.schema.hash));
    });

    test('round-trips through the shapes own toJson/fromJson', () {
      final plan = _generator().plan(_shapes);
      final parsed = ClientSchemaDocument.tryParse(plan.schemaFileContents)!;

      expect(parsed.hash, plan.schema.hash);
      expect(parsed.tables['posts'], _shapes['posts']);
    });

    test('recomputes the hash rather than trusting the file', () {
      final plan = _generator().plan(_shapes);
      final tampered =
          jsonDecode(plan.schemaFileContents) as Map<String, dynamic>
            ..['hash'] = 'deadbeef';

      expect(
        ClientSchemaDocument.tryParse(jsonEncode(tampered))!.hash,
        plan.schema.hash,
      );
    });

    test('is written where the settings say, with a trailing newline', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator();
        generator.write(generator.plan(_shapes));
      });

      final contents = memoryFs.file(_schemaPath).readAsStringSync();
      expect(contents, endsWith('}\n'));
      expect(jsonDecode(contents), isA<Map<String, dynamic>>());
    });
  });

  group('generated files', () {
    test('every file carries the generated-code header', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator();
        final plan = generator.plan(_shapes);
        generator.write(plan);

        for (final entry in plan.files.entries) {
          expect(
            entry.value,
            startsWith(kGeneratedClientHeader),
            reason: '${entry.key} must announce itself as generated',
          );
        }
      });
    });

    test('a manifest records exactly what was written', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator();
        generator.write(generator.plan(_shapes));
      });

      final manifest = ClientManifest.tryParse(
        memoryFs.file('$_output/${ClientManifest.fileName}').readAsStringSync(),
      )!;

      expect(manifest.files, [
        'tables/audit_log.g.dart',
        'tables/authors.g.dart',
        'tables/posts.g.dart',
        DartClientEmitter.barrelFileName,
        DartClientEmitter.runtimeFileName,
      ]);
      expect(manifest.generatorVersion, '9.9.9');
      expect(
        manifest.files,
        isNot(contains(ClientManifest.fileName)),
        reason: 'the manifest does not list itself',
      );
    });

    test('per-table row-name overrides reach the emitter', () {
      final generator = _generator(
        settings: const ClientSettings(
          output: _output,
          names: {'posts': ClientNameOverrides(row: 'BlogPostsRow')},
        ),
      );

      final plan = generator.plan(_shapes);

      expect(plan.files['tables/posts.g.dart']!, contains('BlogPostsRow'));
      expect(plan.files['tables/authors.g.dart']!, contains('AuthorsRow'));
      expect(
        plan.files[DartClientEmitter.barrelFileName]!,
        contains('BlogPostsApi get blogPosts'),
        reason: 'the override moves every name for the table, not just the row',
      );
    });
  });

  group('write guard', () {
    test('allows a directory that does not exist', () {
      final memoryFs = MemoryFileSystem();

      expect(_scoped(memoryFs, () => _generator().guard()), isNull);
    });

    test('allows an empty directory', () {
      final memoryFs = MemoryFileSystem()
        ..directory(_output).createSync(recursive: true);

      expect(_scoped(memoryFs, () => _generator().guard()), isNull);
    });

    test('allows a directory carrying our manifest', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator();
        generator.write(generator.plan(_shapes));
      });

      // A second run over its own output is the normal case, and must not
      // need --force.
      expect(_scoped(memoryFs, () => _generator().guard()), isNull);
    });

    test('refuses a non-empty directory with no manifest, and says why', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.file('$_output/hand_written.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// mine');

      final refusal = _scoped(memoryFs, () => _generator().guard());

      expect(refusal, isNotNull);
      expect(refusal!.directory, _output);
      expect(refusal.entries, contains('hand_written.dart'));
      expect(refusal.message, contains(_output));
      expect(refusal.message, contains('hand_written.dart'));
      expect(
        refusal.message,
        contains('--force'),
        reason: 'a refusal that does not say what to do next is a dead end',
      );
    });

    test('--force overrides the refusal', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.file('$_output/hand_written.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// mine');

      expect(_scoped(memoryFs, () => _generator().guard(force: true)), isNull);
    });

    test('--force still never deletes a file zonai did not write', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.file('$_output/hand_written.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// mine');

      _scoped(memoryFs, () {
        final generator = _generator();
        generator.write(generator.plan(_shapes));
      });

      expect(memoryFs.file('$_output/hand_written.dart').existsSync(), isTrue);
      expect(
        memoryFs.file('$_output/hand_written.dart').readAsStringSync(),
        '// mine',
      );
    });

    test('a corrupt manifest is not a licence to overwrite', () {
      final memoryFs = MemoryFileSystem();
      memoryFs.file('$_output/${ClientManifest.fileName}')
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');

      // The file is still *present*, so the guard passes on name alone --
      // but nothing may be inferred about what it owns.
      expect(_scoped(memoryFs, () => _generator().readManifest()), isNull);
    });
  });

  group('regeneration', () {
    test('removes files the previous manifest owned and this run does not', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator(
          emitter: const _FixedEmitter({
            'a.dart': '$kGeneratedClientHeader\n// a',
            'b.dart': '$kGeneratedClientHeader\n// b',
          }),
        );
        generator.write(generator.plan(_shapes));
      });

      expect(memoryFs.file('$_output/b.dart').existsSync(), isTrue);

      final removed = _scoped(memoryFs, () {
        final generator = _generator(
          emitter: const _FixedEmitter({
            'a.dart': '$kGeneratedClientHeader\n// a',
          }),
        );
        return generator.write(generator.plan(_shapes)).removed;
      });

      expect(memoryFs.file('$_output/a.dart').existsSync(), isTrue);
      expect(memoryFs.file('$_output/b.dart').existsSync(), isFalse);
      expect(removed, ['$_output/b.dart']);
    });
  });

  group('--check', () {
    test('reports nothing when the committed output is current', () {
      final memoryFs = MemoryFileSystem();

      final drift = _scoped(memoryFs, () {
        final generator = _generator();
        final plan = generator.plan(_shapes);
        generator.write(plan);
        return generator.check(generator.plan(_shapes));
      });

      expect(drift, isEmpty);
    });

    test('reports a changed schema, naming the hashes', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator();
        generator.write(generator.plan(_shapes));
      });

      final changed = {
        ..._shapes,
        'posts': TableSchemaShape(
          table: 'posts',
          columns: [_column('id'), _column('title'), _column('published_at')],
        ),
      };

      final drift = _scoped(
        memoryFs,
        () => _generator().check(_generator().plan(changed)),
      );

      expect(drift, isNotEmpty);
      expect(drift.map((entry) => entry.path), contains(_schemaPath));
      expect(
        drift.firstWhere((entry) => entry.path == _schemaPath).detail,
        contains('schema hash'),
      );
      expect(drift.map((entry) => entry.toString()).join('\n'), contains('~'));
    });

    test('reports a missing output file', () {
      final memoryFs = MemoryFileSystem();

      final drift = _scoped(memoryFs, () {
        final generator = _generator();
        final plan = generator.plan(_shapes);
        generator.write(plan);
        memoryFs
            .file('$_output/${DartClientEmitter.barrelFileName}')
            .deleteSync();
        return generator.check(generator.plan(_shapes));
      });

      expect(drift, hasLength(1));
      expect(drift.single.kind, ClientDriftKind.missing);
    });

    test('reports a hand-edited generated file', () {
      final memoryFs = MemoryFileSystem();

      final drift = _scoped(memoryFs, () {
        final generator = _generator();
        generator.write(generator.plan(_shapes));
        memoryFs
            .file('$_output/${DartClientEmitter.barrelFileName}')
            .writeAsStringSync('// edited by hand');
        return generator.check(generator.plan(_shapes));
      });

      expect(drift, hasLength(1));
      expect(drift.single.kind, ClientDriftKind.changed);
    });

    test('reports a file a previous run generated and this one would not', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator(
          emitter: const _FixedEmitter({
            'a.dart': '$kGeneratedClientHeader\n// a',
            'b.dart': '$kGeneratedClientHeader\n// b',
          }),
        );
        generator.write(generator.plan(_shapes));
      });

      final drift = _scoped(memoryFs, () {
        final generator = _generator(
          emitter: const _FixedEmitter({
            'a.dart': '$kGeneratedClientHeader\n// a',
          }),
        );
        return generator.check(generator.plan(_shapes));
      });

      expect(drift, hasLength(1));
      expect(drift.single.kind, ClientDriftKind.extra);
      expect(drift.single.path, '$_output/b.dart');
    });

    test('a CRLF checkout of an up-to-date client is not drift', () {
      // Git for Windows installs with core.autocrlf=true, so a consumer who
      // commits their generated client gets CRLF back on checkout while the
      // emitter still produces LF. Before this, `--check` called every file
      // changed and there was no way out of it: regenerating rewrites LF and
      // the next checkout undoes it. Our own goldens hit the same skew on
      // windows-latest; `.gitattributes` fixes that, and cannot fix this,
      // because a consumer's repository is not ours to configure.
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator();
        generator.write(generator.plan(_shapes));
      });

      // Exactly what the checkout does: rewrite every generated file's line
      // endings, touching nothing else.
      for (final file
          in memoryFs
              .directory(_output)
              .listSync(recursive: true)
              .whereType<File>()) {
        file.writeAsStringSync(
          file.readAsStringSync().replaceAll('\n', '\r\n'),
        );
      }

      final drift = _scoped(
        memoryFs,
        () => _generator().check(_generator().plan(_shapes)),
      );

      expect(drift, isEmpty);
    });

    test('a real change is still drift on a CRLF checkout', () {
      // The control for the test above. Forgiving line endings must not
      // forgive content -- an implementation that compared nothing would pass
      // the previous assertion perfectly.
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () {
        final generator = _generator(
          emitter: const _FixedEmitter({
            'a.dart': '$kGeneratedClientHeader\n// a',
          }),
        );
        generator.write(generator.plan(_shapes));
      });

      final onDisk = memoryFs.file('$_output/a.dart');
      onDisk.writeAsStringSync(
        onDisk.readAsStringSync().replaceAll('\n', '\r\n'),
      );

      final drift = _scoped(memoryFs, () {
        final generator = _generator(
          emitter: const _FixedEmitter({
            'a.dart': '$kGeneratedClientHeader\n// a CHANGED',
          }),
        );
        return generator.check(generator.plan(_shapes));
      });

      expect(drift, hasLength(1));
      expect(drift.single.kind, ClientDriftKind.changed);
    });

    test('writes nothing at all', () {
      final memoryFs = MemoryFileSystem();

      _scoped(memoryFs, () => _generator().check(_generator().plan(_shapes)));

      expect(memoryFs.file(_schemaPath).existsSync(), isFalse);
      expect(memoryFs.directory(_output).existsSync(), isFalse);
    });
  });
}
