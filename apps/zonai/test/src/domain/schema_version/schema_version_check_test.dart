import 'package:file/memory.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/schema_version/min_schema_version.dart';
import 'package:zonai/src/domain/schema_version/schema_version_check.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

void main() {
  group('SchemaVersionCheck.check', () {
    late MemoryFileSystem memoryFs;
    late List<String> warnings;
    late List<String> errors;

    Set<ScopedRef<dynamic>> overrides() => {
      fsProvider.overrideWith(() => memoryFs),
      argsProvider.overrideWith(() => const Args()),
      loggerProvider.overrideWith(
        () => _RecordingLogger(warnings: warnings, errors: errors),
      ),
      settingsProvider.overrideWith(Settings.load),
    };

    setUp(() {
      memoryFs = MemoryFileSystem();
      warnings = [];
      errors = [];
    });

    void writeLock(String body) =>
        fs.file('pubspec.lock').writeAsStringSync(body);

    group('says nothing when there is no version to compare', () {
      test('no pubspec.lock at all', () {
        runScoped(() {
          final result = const SchemaVersionCheck().check();
          expect(result, isNull);
          expect(errors, isEmpty);
        }, values: overrides());
      });

      test('lock file with no zonai_schema entry', () {
        runScoped(() {
          writeLock('''
packages:
  some_other_package:
    source: hosted
    version: "1.0.0"
''');

          final result = const SchemaVersionCheck().check();
          expect(result, isNull);
          expect(errors, isEmpty);
        }, values: overrides());
      });

      // A path dependency carries no version, which is every checkout of this
      // monorepo. Refusing to start on a version nobody can read would block
      // exactly the people working on the schema.
      test('path-sourced zonai_schema, even against a huge floor', () {
        runScoped(() {
          writeLock('''
packages:
  zonai_schema:
    dependency: "direct main"
    description:
      path: "../../libs/zonai_schema"
      relative: true
    source: path
''');

          final result = SchemaVersionCheck(
            minVersion: Version.parse('9.9.9'),
          ).check();
          expect(result, isNull);
          expect(errors, isEmpty);
        }, values: overrides());
      });
    });

    group('compares against the floor', () {
      test('errors when resolved is below it', () {
        runScoped(() {
          writeLock('''
packages:
  zonai_schema:
    source: hosted
    version: "0.1.1"
''');

          final result = SchemaVersionCheck(
            minVersion: Version.parse('0.2.0'),
          ).check();

          expect(result, 1);
          expect(errors, hasLength(1));
          expect(errors.single, contains('0.1.1'));
          expect(errors.single, contains('0.2.0'));
          expect(warnings, isEmpty);
        }, values: overrides());
      });

      test('accepts resolved exactly at the floor', () {
        runScoped(() {
          writeLock('''
packages:
  zonai_schema:
    source: hosted
    version: "0.2.0"
''');

          final result = SchemaVersionCheck(
            minVersion: Version.parse('0.2.0'),
          ).check();
          expect(result, isNull);
          expect(errors, isEmpty);
        }, values: overrides());
      });

      // The old ladder blocked here: 0.2.0 and 0.3.0 are different `^` cohorts
      // below 1.0, so a newer-but-not-same-cohort schema counted as breaking.
      // A floor only bounds the bottom -- above it is the consumer's business.
      test('accepts a resolved version well above the floor', () {
        runScoped(() {
          writeLock('''
packages:
  zonai_schema:
    source: hosted
    version: "0.3.0"
''');

          final result = SchemaVersionCheck(
            minVersion: Version.parse('0.2.0'),
          ).check();
          expect(result, isNull);
          expect(errors, isEmpty);
        }, values: overrides());
      });

      // The old check compared against kVersion, so a 0.x schema against a
      // 0.6.x CLI was always "too far behind" -- which is the state every
      // pub.dev consumer was actually in.
      test(
        'does not treat a 0.x schema as stale just for trailing the CLI',
        () {
          runScoped(() {
            writeLock('''
packages:
  zonai_schema:
    source: hosted
    version: "$kMinSchemaVersion"
''');

            final result = const SchemaVersionCheck().check();
            expect(result, isNull);
            expect(errors, isEmpty);
          }, values: overrides());
        },
      );
    });
  });

  test('the declared floor is a parseable version', () {
    expect(() => Version.parse(kMinSchemaVersion), returnsNormally);
  });
}

class _RecordingLogger implements Logger {
  _RecordingLogger({required this.warnings, required this.errors});

  final List<String> warnings;
  final List<String> errors;

  @override
  void warn(String message, {String? prefix}) => warnings.add(message);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      errors.add(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
