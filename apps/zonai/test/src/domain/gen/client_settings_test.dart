import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/settings.dart';

Settings _load(String yaml) {
  final memoryFs = MemoryFileSystem();
  return runScoped(() {
    memoryFs.file('zonai.yaml').writeAsStringSync(yaml);
    return Settings.load();
  }, values: {fsProvider.overrideWith(() => memoryFs)});
}

void main() {
  group('Settings.load client block', () {
    test('is null when zonai.yaml has no client block', () {
      final settings = _load('version: 0.1.0\n');

      expect(
        settings.client,
        isNull,
        reason:
            'every existing project is in this state; a default block '
            'would make `gen client` silently generate somewhere',
      );
    });

    test('normalizes output the same way the other paths are normalized', () {
      final settings = _load('''
version: 0.1.0
client:
  output: ../app/lib/gen/./zonai
''');

      expect(settings.client?.output, '../app/lib/gen/zonai');
    });

    test('defaults every optional key', () {
      final settings = _load('''
version: 0.1.0
client:
  output: out
''');

      final client = settings.client!;
      expect(client.package, isFalse);
      expect(client.packageName, isNull);
      expect(client.excludeTables, isEmpty);
      expect(client.names, isEmpty);
    });

    test('parses the full block from the design doc', () {
      final settings = _load('''
version: 0.1.0
client:
  output: ../app/lib/gen/zonai
  package: true
  packageName: my_api
  tables:
    exclude: [audit_log, _rate_limit]
  names:
    posts:
      row: BlogPostsRow
''');

      final client = settings.client!;
      expect(client.output, '../app/lib/gen/zonai');
      expect(client.package, isTrue);
      expect(client.packageName, 'my_api');
      expect(client.excludeTables, ['audit_log', '_rate_limit']);
      expect(client.rowNameFor('posts'), 'BlogPostsRow');
      expect(client.rowNameFor('authors'), isNull);
      expect(client.includesTable('audit_log'), isFalse);
      expect(client.includesTable('posts'), isTrue);
    });

    test('a client block without output parses, leaving output null', () {
      // Deliberately not a load-time throw: `zonai serve` must still start.
      // `zonai gen client` is what reports the omission, with the fix.
      final settings = _load('''
version: 0.1.0
client:
  package: false
''');

      expect(settings.client, isNotNull);
      expect(settings.client?.hasOutput, isFalse);
    });

    test('rejects a wrongly-typed client block instead of ignoring it', () {
      expect(
        () => _load('version: 0.1.0\nclient: ../app/lib/gen/zonai\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a wrongly-typed output', () {
      expect(
        () => _load('version: 0.1.0\nclient:\n  output: 42\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a wrongly-typed tables.exclude', () {
      expect(
        () => _load('version: 0.1.0\nclient:\n  tables:\n    exclude: nope\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a wrongly-typed names entry', () {
      expect(
        () => _load('version: 0.1.0\nclient:\n  names:\n    posts: Blog\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('clientSchemaPath points into .zonai', () {
      final memoryFs = MemoryFileSystem();

      final path = runScoped(() {
        memoryFs
            .file('zonai.yaml')
            .writeAsStringSync('version: 0.1.0\nclient:\n  output: out\n');
        // Resolved inside the scope: the path getters go through `fs.path`.
        return Settings.load().clientSchemaPath;
      }, values: {fsProvider.overrideWith(() => memoryFs)});

      expect(path, '.zonai/schema.json');
    });
  });
}
