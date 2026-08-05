import 'package:file/memory.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
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
      loggerProvider.overrideWith(() => _RecordingLogger(warnings: warnings, errors: errors)),
      settingsProvider.overrideWith(Settings.load),
    };

    setUp(() {
      memoryFs = MemoryFileSystem();
      warnings = [];
      errors = [];
    });

    test('returns null when pubspec.lock does not exist', () {
      runScoped(() {
        final result = const SchemaVersionCheck(
          requiredVersion: null,
        ).check();
        expect(result, isNull);
        expect(warnings, isEmpty);
        expect(errors, isEmpty);
      }, values: overrides());
    });

    test('returns null when pubspec.lock has no zonai_schema entry', () {
      runScoped(() {
        fs.file('pubspec.lock').writeAsStringSync('''
packages:
  some_other_package:
    source: hosted
    version: "1.0.0"
''');

        final result = const SchemaVersionCheck().check();
        expect(result, isNull);
        expect(warnings, isEmpty);
        expect(errors, isEmpty);
      }, values: overrides());
    });

    test('returns null and logs nothing for a path-sourced zonai_schema entry', () {
      runScoped(() {
        fs.file('pubspec.lock').writeAsStringSync('''
packages:
  zonai_schema:
    dependency: "direct main"
    description:
      path: "../../libs/zonai_schema"
      relative: true
    source: path
''');

        final result = SchemaVersionCheck(requiredVersion: Version.parse('9.9.9')).check();
        expect(result, isNull);
        expect(warnings, isEmpty);
        expect(errors, isEmpty);
      }, values: overrides());
    });

    test('blocks and logs an error when resolved is far behind required', () {
      runScoped(() {
        fs.file('pubspec.lock').writeAsStringSync('''
packages:
  zonai_schema:
    source: hosted
    version: "1.0.0"
''');

        final result = SchemaVersionCheck(requiredVersion: Version.parse('9.9.9')).check();
        expect(result, 1);
        expect(errors, hasLength(1));
        expect(errors.single, contains('too far behind'));
        expect(warnings, isEmpty);
      }, values: overrides());
    });

    test('warns without blocking when resolved is behind but same-cohort', () {
      runScoped(() {
        fs.file('pubspec.lock').writeAsStringSync('''
packages:
  zonai_schema:
    source: hosted
    version: "1.2.0"
''');

        final result = SchemaVersionCheck(requiredVersion: Version.parse('1.2.3')).check();
        expect(result, isNull);
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('older than this CLI'));
        expect(errors, isEmpty);
      }, values: overrides());
    });

    test('returns null when resolved already satisfies required', () {
      runScoped(() {
        fs.file('pubspec.lock').writeAsStringSync('''
packages:
  zonai_schema:
    source: hosted
    version: "2.0.0"
''');

        final result = SchemaVersionCheck(requiredVersion: Version.parse('1.2.3')).check();
        expect(result, isNull);
        expect(warnings, isEmpty);
        expect(errors, isEmpty);
      }, values: overrides());
    });
  });
}

class _RecordingLogger implements Logger {
  _RecordingLogger({required this.warnings, required this.errors});

  final List<String> warnings;
  final List<String> errors;

  @override
  void warn(String message, {String? prefix}) => warnings.add(message);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) => errors.add(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
