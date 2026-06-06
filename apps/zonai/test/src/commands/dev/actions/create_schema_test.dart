import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/dev/actions/create_schema.dart';
import 'package:zonai/src/commands/dev/actions/schema_scaffold.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/settings.dart';
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
  buildSettings: BuildSettings.current(),
  version: kVersion,
);

void main() {
  group('createSchema', () {
    test('creates a schema file and standalone ID type', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.directory('lib/src/schemas').createSync(recursive: true);

          final result = createSchema(
            rawEntityName: 'Product',
            kind: SchemaTableKind.regular,
          );

          expect(result.ok, isTrue);
          expect(result.schemaPath, 'lib/src/schemas/products.dart');
          expect(result.idsPath, 'lib/src/ids.dart');

          final schema = memoryFs
              .file('lib/src/schemas/products.dart')
              .readAsStringSync();
          expect(schema, contains('final products = table('));
          expect(schema, contains('class ProductTable extends Table<Product>'));

          final ids = memoryFs.file('lib/src/ids.dart').readAsStringSync();
          expect(ids, contains('sealed class ProductsId implements z.Id'));
          expect(ids, contains("static const _suffix = 'pr'"));
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          settingsProvider.overrideWith(() => _testSettings),
        },
      );
    });

    test('appends to an existing union IDs file', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.directory('lib/src/schemas').createSync(recursive: true);
          memoryFs.file('lib/src/ids.dart').writeAsStringSync('''
import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: \$json');
    }

    return switch (parts[1]) {
      ItemsId._suffix => ItemsId(json),
      _ => throw ArgumentError('Invalid ID format: \$json'),
    };
  }

  final String value;
}

class ItemsId extends Id {
  const ItemsId(super.value);

  factory ItemsId.generate() => ItemsId(z.Id.generate(_suffix));

  static const _suffix = 'it';
}
''');

          final result = createSchema(
            rawEntityName: 'Product',
            kind: SchemaTableKind.regular,
          );

          expect(result.ok, isTrue);

          final ids = memoryFs.file('lib/src/ids.dart').readAsStringSync();
          expect(ids, contains('ProductsId._suffix => ProductsId(json),'));
          expect(ids, contains('class ProductsId extends Id'));
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          settingsProvider.overrideWith(() => _testSettings),
        },
      );
    });

    test('rejects auth tables without any auth methods', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.directory('lib/src/schemas').createSync(recursive: true);

          final result = createSchema(
            rawEntityName: 'Product',
            kind: SchemaTableKind.auth,
            authConfig: const SchemaAuthConfig(
              password: false,
              otp: false,
              magicLink: false,
            ),
          );

          expect(result.ok, isFalse);
          expect(result.error, contains('Select at least one auth method'));
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          settingsProvider.overrideWith(() => _testSettings),
        },
      );
    });

    test('rejects when the schema file already exists', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs
              .file('lib/src/schemas/products.dart')
              .createSync(recursive: true);

          final result = createSchema(
            rawEntityName: 'Product',
            kind: SchemaTableKind.regular,
          );

          expect(result.ok, isFalse);
          expect(result.error, contains('Schema already exists'));
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          settingsProvider.overrideWith(() => _testSettings),
        },
      );
    });
  });
}
