import 'dart:convert';

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/message_contract_hash.dart';
import 'package:zonai/src/domain/settings.dart';

/// A project at `/project`, with `zonai_schema` resolved to [schemaRoot].
void _writePackageConfig(
  String schemaRoot, {
  String configDirectory = '/project',
}) {
  fs.file(fs.path.join(configDirectory, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      json.encode({
        'configVersion': 2,
        'packages': [
          {'name': 'other', 'rootUri': '../../other', 'packageUri': 'lib/'},
          {'name': 'zonai_schema', 'rootUri': schemaRoot, 'packageUri': 'lib/'},
        ],
      }),
    );
}

void _writeSchemaFile(String relativePath, String source) {
  fs.file('/schema/lib/$relativePath')
    ..createSync(recursive: true)
    ..writeAsStringSync(source);
}

/// The minimum shape the walk needs: one handler that imports a type.
void _writeMinimalSchema() {
  _writeSchemaFile('src/handlers/rate_limits/rate_limit_request.dart', '''
import 'package:zonai_schema/src/types/rate_limit_operation.dart';
import 'package:msgpack_dart/msgpack_dart.dart';
import 'dart:convert';

class RateLimitRequest {
  RateLimitRequest(this.operation);
  final RateLimitOperation operation;
  Map<String, dynamic> toJson() => {'operation': operation.name};
}
''');
  _writeSchemaFile('src/types/rate_limit_operation.dart', '''
enum RateLimitOperation { get, list }
''');
}

void main() {
  late MemoryFileSystem memoryFs;

  final settings = Settings(
    path: 'zonai.yaml',
    basePath: '/project',
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

  Set<ScopedRef<dynamic>> overrides() => {
    fsProvider.overrideWith(() => memoryFs),
    settingsProvider.overrideWith(() => settings),
  };

  T scoped<T>(T Function() body) => runScoped(body, values: overrides());

  setUp(() {
    memoryFs = MemoryFileSystem();
  });

  group('locatePackageConfig', () {
    test('finds the config in the project root', () {
      scoped(() {
        _writePackageConfig('../../schema');
        expect(
          MessageContractHash().locatePackageConfig(),
          '/project/.dart_tool/package_config.json',
        );
      });
    });

    // Pub workspaces put one config at the workspace root and none in the
    // member, which is what apps/playground actually looks like.
    test('walks up to a workspace root when the member has no config', () {
      scoped(() {
        _writePackageConfig('../schema', configDirectory: '/');
        expect(
          MessageContractHash().locatePackageConfig(),
          '/.dart_tool/package_config.json',
        );
      });
    });

    test('null when nothing above the project has one', () {
      scoped(() {
        expect(MessageContractHash().locatePackageConfig(), isNull);
      });
    });
  });

  group('resolveSchemaLibRoot', () {
    test(
      'resolves rootUri relative to the config directory, then packageUri',
      () {
        scoped(() {
          _writePackageConfig('../../schema');
          expect(MessageContractHash().resolveSchemaLibRoot(), '/schema/lib');
        });
      },
    );

    test('null when zonai_schema is not in the config', () {
      scoped(() {
        fs.file('/project/.dart_tool/package_config.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            json.encode({'configVersion': 2, 'packages': []}),
          );
        expect(MessageContractHash().resolveSchemaLibRoot(), isNull);
      });
    });

    test('null when the config is not JSON', () {
      scoped(() {
        fs.file('/project/.dart_tool/package_config.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('not json at all');
        expect(MessageContractHash().resolveSchemaLibRoot(), isNull);
      });
    });
  });

  group('contractFiles', () {
    test('follows imports out of handlers into the types they parse', () {
      scoped(() {
        _writePackageConfig('../../schema');
        _writeMinimalSchema();

        expect(
          MessageContractHash().contractFiles('/schema/lib').keys,
          containsAll([
            'src/handlers/rate_limits/rate_limit_request.dart',
            'src/types/rate_limit_operation.dart',
          ]),
        );
      });
    });

    test('follows exports and parts as well as imports', () {
      scoped(() {
        _writePackageConfig('../../schema');
        _writeSchemaFile('src/handlers/a.dart', '''
export 'package:zonai_schema/src/exported.dart';
part 'package:zonai_schema/src/parted.dart';
''');
        _writeSchemaFile('src/exported.dart', 'class Exported {}');
        _writeSchemaFile('src/parted.dart', 'class Parted {}');

        expect(
          MessageContractHash().contractFiles('/schema/lib').keys,
          containsAll(['src/exported.dart', 'src/parted.dart']),
        );
      });
    });

    test('follows relative imports', () {
      scoped(() {
        _writePackageConfig('../../schema');
        _writeSchemaFile('src/handlers/a.dart', "import '../sibling.dart';");
        _writeSchemaFile('src/sibling.dart', 'class Sibling {}');

        expect(
          MessageContractHash().contractFiles('/schema/lib').keys,
          contains('src/sibling.dart'),
        );
      });
    });

    // Somebody else's contract, and hashing it would make an unrelated
    // dependency bump refuse every worker on disk.
    test('does not follow dart: or third-party package: imports', () {
      scoped(() {
        _writePackageConfig('../../schema');
        _writeMinimalSchema();

        // Only the handler and the type it imports -- `dart:convert` and
        // `package:msgpack_dart` are nobody's business here.
        expect(
          MessageContractHash().contractFiles('/schema/lib'),
          hasLength(2),
        );
      });
    });

    test('does not follow a relative import that climbs out of lib/', () {
      scoped(() {
        _writePackageConfig('../../schema');
        _writeSchemaFile(
          'src/handlers/a.dart',
          "import '../../../outside.dart';",
        );
        fs.file('/schema/outside.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('class Outside {}');

        expect(MessageContractHash().contractFiles('/schema/lib').keys, [
          'src/handlers/a.dart',
        ]);
      });
    });

    test('survives an import cycle', () {
      scoped(() {
        _writePackageConfig('../../schema');
        _writeSchemaFile('src/handlers/a.dart', "import '../b.dart';");
        _writeSchemaFile('src/b.dart', "import 'handlers/a.dart';");

        expect(
          MessageContractHash().contractFiles('/schema/lib'),
          hasLength(2),
        );
      });
    });
  });

  group('compute', () {
    String? hashWith(void Function() mutate) {
      return scoped(() {
        _writePackageConfig('../../schema');
        _writeMinimalSchema();
        mutate();
        return MessageContractHash().compute();
      });
    }

    test('null when there is no package config to resolve', () {
      scoped(() {
        expect(MessageContractHash().compute(), isNull);
      });
    });

    // Not the hash of an empty set: a `zonai_schema` with no handlers is
    // unknown, and a constant would silently "match" the next unknown.
    test('null when the resolved schema has no handlers directory', () {
      scoped(() {
        _writePackageConfig('../../schema');
        _writeSchemaFile(
          'src/types/rate_limit_operation.dart',
          'enum Op { get }',
        );
        expect(MessageContractHash().compute(), isNull);
      });
    });

    test('stable across runs over unchanged sources', () {
      expect(hashWith(() {}), hashWith(() {}));
    });

    // The #25 bug: a value the host can now send that an older worker cannot
    // parse, with IpcCodec.version correctly unchanged.
    test('changes when an enum a handler parses gains a value', () {
      final baseline = hashWith(() {});
      expect(
        hashWith(() {
          _writeSchemaFile(
            'src/types/rate_limit_operation.dart',
            'enum RateLimitOperation { get, list, custom }',
          );
        }),
        isNot(baseline),
      );
    });

    test('changes when a payload key is renamed', () {
      final baseline = hashWith(() {});
      expect(
        hashWith(() {
          final file = fs.file(
            '/schema/lib/src/handlers/rate_limits/rate_limit_request.dart',
          );
          file.writeAsStringSync(
            file.readAsStringSync().replaceAll("'operation'", "'op'"),
          );
        }),
        isNot(baseline),
      );
    });

    test('changes when a new file joins the closure', () {
      final baseline = hashWith(() {});
      expect(
        hashWith(() {
          _writeSchemaFile('src/handlers/cron/cron_request.dart', 'class C {}');
        }),
        isNot(baseline),
      );
    });

    // Broad file sets only stay tolerable if the churn that dominates them --
    // doc comments and `dart format` -- does not force a rebuild.
    test('unchanged by comment and formatting edits', () {
      final baseline = hashWith(() {});
      expect(
        hashWith(() {
          _writeSchemaFile('src/types/rate_limit_operation.dart', '''
/// A brand new doc comment nobody had written before.
enum RateLimitOperation {
  get,

      list
}
''');
        }),
        baseline,
      );
    });

    // A pub-cache copy and a path dependency of the same sources have to
    // agree, or every consumer would see a mismatch against their own workers.
    test('unchanged when the same sources move to a different directory', () {
      final atSchema = hashWith(() {});

      final elsewhere = runScoped(() {
        _writePackageConfig('../../elsewhere');
        for (final path in [
          'src/handlers/rate_limits/rate_limit_request.dart',
          'src/types/rate_limit_operation.dart',
        ]) {
          fs.file('/elsewhere/lib/$path')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              fs.file('/schema/lib/$path').readAsStringSync(),
            );
        }
        return MessageContractHash().compute();
      }, values: overrides());

      expect(atSchema, isNotNull);
      expect(elsewhere, atSchema);
    });
  });

  test('value computes once and caches', () {
    scoped(() {
      _writePackageConfig('../../schema');
      _writeMinimalSchema();

      final contract = MessageContractHash();
      final first = contract.value;
      expect(first, isNotNull);

      _writeSchemaFile(
        'src/types/rate_limit_operation.dart',
        'enum RateLimitOperation { get, list, custom }',
      );

      expect(contract.value, first);
      expect(contract.compute(), isNot(first));
    });
  });
}
