import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/create_part.dart';
import 'package:zonai/src/commands/dev/actions/part_scaffold.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/schema_tables.dart';
import 'package:zonai/gen/version.dart';

final _testSettings = Settings(
  path: 'zonai.yaml',
  migrationsPath: '.zonai/migrations',
  dataPath: '.zonai/data',
  schemasPath: 'lib/src/schemas',
  extensionsPath: 'lib/src/extensions',
  rulesPath: 'lib/src/rules',
  operationsPath: 'lib/src/operations',
  configPath: 'lib/src/config',
  emailTemplatesPath: 'lib/src/email_templates',
  rateLimitPath: 'lib/src/rate_limit',
  cronsPath: 'lib/src/crons',
  imagesPath: '.zonai/data/images',
  buildSettings: BuildSettings.current(),
  version: kVersion,
);

const _authorTable = SchemaTableInfo(
  tableName: 'authors',
  getter: 'authors',
  entityClass: 'Author',
  tableClass: 'AuthorTable',
  isAuthTable: false,
  schemaFilePath: 'lib/src/schemas/authors.dart',
);

void main() {
  group('createWorkerPart', () {
    test('creates a new operations part file', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.directory('lib/src/schemas').createSync(recursive: true);
          memoryFs.file('lib/src/schemas/authors.dart').writeAsStringSync('');

          final result = createWorkerPart(
            type: WorkerPartType.operations,
            rawClassName: 'AuthorOperations',
            table: _authorTable,
          );

          expect(result.ok, isTrue);
          expect(result.path, 'lib/src/operations/author_operations.dart');
          expect(
            memoryFs
                .file('lib/src/operations/author_operations.dart')
                .existsSync(),
            isTrue,
          );
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          settingsProvider.overrideWith(() => _testSettings),
        },
      );
    });

    test('rejects when the output file already exists', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs
              .file('lib/src/operations/author_operations.dart')
              .createSync(recursive: true);

          final result = createWorkerPart(
            type: WorkerPartType.operations,
            rawClassName: 'AuthorOperations',
            table: _authorTable,
          );

          expect(result.ok, isFalse);
          expect(result.error, contains('File already exists'));
          expect(result.error, contains('author_operations.dart'));
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          settingsProvider.overrideWith(() => _testSettings),
        },
      );
    });
  });
}
