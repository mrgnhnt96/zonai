import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/domain/dart_sdk/dart_sdk_check.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// The measured hashes this check exists because of. 3.12.0 and 3.12.1 share a
/// minor and do NOT share a hash; 3.13.1 and 3.13.2 share a hash and are
/// interchangeable. Both pairs are asserted below, because a version
/// comparison would get each one wrong in the opposite direction.
const _hash3120 = '41be3daaabd524b8aa7423bc24584957';
const _hash3121 = 'ace654289f5abc240509fc941453ebc5';
const _hash313x = '0451907c2eaa8467e848c0067bfe8ed4';

void main() {
  group('DartSdkCheck.check', () {
    late MemoryFileSystem memoryFs;
    late List<String> warnings;
    late List<String> errors;

    Set<ScopedRef<dynamic>> overrides({List<String> path = const ['serve']}) =>
        {
          fsProvider.overrideWith(() => memoryFs),
          argsProvider.overrideWith(() => Args(path: path)),
          loggerProvider.overrideWith(
            () => _RecordingLogger(warnings: warnings, errors: errors),
          ),
        };

    setUp(() {
      memoryFs = MemoryFileSystem();
      warnings = [];
      errors = [];
    });

    /// An SDK on disk shaped like a real one: a `dart` launcher, the
    /// `dartaotruntime` that carries the hash, and the one-line `version` file
    /// the official archive ships in its root.
    void writeSdk({required String hash, String? version}) {
      void binary(String path, String contents) => fs.file(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(contents.codeUnits);

      binary('/sdk/bin/dart', 'the dart launcher, not a runtime');
      binary('/sdk/bin/dartaotruntime', '\x00\x7fELF\x01$hash\x00pad\x00');
      if (version != null) {
        binary('/sdk/version', '$version\n');
      }
    }

    group('says nothing when there is nothing to compare', () {
      // The state of every zonai binary compiled without the stamp, and of
      // every run on the Dart VM. Unknown is not mismatch: this reports to a
      // human, and a false alarm about a working toolchain is worse than the
      // silence.
      test('an unstamped host, against a plainly different SDK', () {
        runScoped(() {
          writeSdk(hash: _hash313x, version: '3.13.2');

          expect(const DartSdkCheck().check('/sdk/bin/dart'), isNull);
          expect(warnings, isEmpty);
          expect(errors, isEmpty);
        }, values: overrides());
      });

      test('a stamped host, against an SDK with no dartaotruntime', () {
        runScoped(() {
          fs.file('/sdk/bin/dart')
            ..createSync(recursive: true)
            ..writeAsBytesSync('launcher'.codeUnits);

          const check = DartSdkCheck(
            hostHash: _hash3120,
            hostVersion: '3.12.0',
          );

          expect(check.check('/sdk/bin/dart'), isNull);
          expect(warnings, isEmpty);
          expect(errors, isEmpty);
        }, values: overrides());
      });

      test('a stamped host, against an SDK that is not installed at all', () {
        runScoped(() {
          const check = DartSdkCheck(
            hostHash: _hash3120,
            hostVersion: '3.12.0',
          );

          expect(check.check('/sdk/bin/dart'), isNull);
          expect(warnings, isEmpty);
          expect(errors, isEmpty);
        }, values: overrides());
      });
    });

    group('compares hashes, not versions', () {
      // The whole reason this is not a semver range. Two different version
      // strings that share a snapshot hash spawn each other's snapshots in
      // both directions, so reporting them as out of sync would be a false
      // alarm on a working toolchain.
      test('3.13.1 and 3.13.2 differ in version but share a hash', () {
        runScoped(() {
          writeSdk(hash: _hash313x, version: '3.13.2');

          const check = DartSdkCheck(
            hostHash: _hash313x,
            hostVersion: '3.13.1',
          );

          expect(check.check('/sdk/bin/dart'), isNull);
          expect(warnings, isEmpty);
          expect(errors, isEmpty);
        }, values: overrides());
      });

      // The other direction, which a `^3.12.0` range would wave through: same
      // minor, different container contents, and the spawn fails.
      test('3.12.0 and 3.12.1 share a minor but not a hash', () {
        runScoped(() {
          writeSdk(hash: _hash3121, version: '3.12.1');

          const check = DartSdkCheck(
            hostHash: _hash3120,
            hostVersion: '3.12.0',
          );

          expect(check.check('/sdk/bin/dart'), isNull);
          expect(warnings, hasLength(1));
          expect(warnings.single, contains('3.12.0'));
          expect(warnings.single, contains('3.12.1'));
        }, values: overrides());
      });

      test('an identical SDK is silent', () {
        runScoped(() {
          writeSdk(hash: _hash3120, version: '3.12.0');

          const check = DartSdkCheck(
            hostHash: _hash3120,
            hostVersion: '3.12.0',
          );

          expect(check.check('/sdk/bin/dart'), isNull);
          expect(warnings, isEmpty);
          expect(errors, isEmpty);
        }, values: overrides());
      });
    });

    group('severity follows the command', () {
      const mismatched = DartSdkCheck(
        hostHash: _hash3120,
        hostVersion: '3.12.0',
      );

      for (final command in ['compile', 'build']) {
        // The only two commands that write an `.aot`, and so the last moment
        // before a snapshot the host cannot load exists on disk.
        test('`zonai $command` refuses', () {
          runScoped(() {
            writeSdk(hash: _hash313x, version: '3.13.2');

            expect(mismatched.check('/sdk/bin/dart'), 1);
            expect(errors, hasLength(1));
            expect(warnings, isEmpty);
            expect(errors.single, contains('--no-dart-sdk-check'));
          }, values: overrides(path: [command]));
        });
      }

      for (final command in [
        ['serve'],
        ['dev'],
        ['db', 'migrate'],
        ['version'],
      ]) {
        test('`zonai ${command.join(' ')}` warns and proceeds', () {
          runScoped(() {
            writeSdk(hash: _hash313x, version: '3.13.2');

            expect(mismatched.check('/sdk/bin/dart'), isNull);
            expect(warnings, hasLength(1));
            expect(errors, isEmpty);
          }, values: overrides(path: command));
        });
      }
    });

    group('the message', () {
      test('names both versions, both hashes, and the way out', () {
        runScoped(() {
          writeSdk(hash: _hash313x, version: '3.13.2');

          const check = DartSdkCheck(
            hostHash: _hash3120,
            hostVersion: '3.12.0',
          );

          expect(check.check('/sdk/bin/dart'), isNull);
          final message = warnings.single;
          expect(message, contains('built with Dart 3.12.0'));
          expect(message, contains('you are on 3.13.2'));
          expect(message, contains(_hash3120));
          expect(message, contains(_hash313x));
          expect(message, contains('dartSdkPath in zonai.yaml'));
          expect(message, contains('--no-dart-sdk-check'));
        }, values: overrides());
      });

      // A repackaged or trimmed SDK ships no `version` file. The hashes still
      // disagree, so the report is still true -- it just cannot name what the
      // developer is on, and must not pretend to.
      test('stays truthful when the local SDK names no version', () {
        runScoped(() {
          writeSdk(hash: _hash313x);

          const check = DartSdkCheck(
            hostHash: _hash3120,
            hostVersion: '3.12.0',
          );

          expect(check.check('/sdk/bin/dart'), isNull);
          final message = warnings.single;
          expect(message, contains('does not name its version'));
          expect(message, contains(_hash313x));
        }, values: overrides());
      });

      test('stays truthful when the host carries no version', () {
        runScoped(() {
          writeSdk(hash: _hash313x, version: '3.13.2');

          const check = DartSdkCheck(hostHash: _hash3120);

          expect(check.check('/sdk/bin/dart'), isNull);
          final message = warnings.single;
          expect(message, contains('a different Dart SDK'));
          expect(message, contains(_hash3120));
        }, values: overrides());
      });
    });
  });

  group('DartSdkCheck.ensure', () {
    // `kIsCompiled` is false under `dart test`, which is the guard's own case:
    // running from source, the host is the same VM that would compile the
    // workers. Nothing is resolved and no subprocess is spawned.
    test('no-ops from source, even with a mismatch on disk', () async {
      final memoryFs = MemoryFileSystem();
      final result = await runScoped(
        () async {
          fs.file('/sdk/bin/dartaotruntime')
            ..createSync(recursive: true)
            ..writeAsBytesSync('\x00$_hash313x\x00'.codeUnits);

          return const DartSdkCheck(
            hostHash: _hash3120,
            hostVersion: '3.12.0',
          ).ensure();
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          argsProvider.overrideWith(() => const Args(path: ['compile'])),
          loggerProvider.overrideWith(
            () => _RecordingLogger(warnings: [], errors: []),
          ),
        },
      );

      expect(result, isNull);
    });
  });

  group('--no-dart-sdk-check', () {
    // `Args.parse` files `--no-x` under `x` as `false`, so the flag as typed
    // never appears as a key. Asserted against the parser rather than a hand
    // built map, since that mapping is the part that can silently change.
    void expectDisabled(List<String> argv, {required bool disabled}) {
      runScoped(() {
        expect(const DartSdkCheck().isDisabled, disabled);
      }, values: {argsProvider.overrideWith(() => Args.parse(argv))});
    }

    test('turns the check off', () {
      expectDisabled(['compile', '--no-dart-sdk-check'], disabled: true);
    });

    test('is off by default', () {
      expectDisabled(['compile'], disabled: false);
    });

    test('an unrelated --no- flag does not turn it off', () {
      expectDisabled(['compile', '--no-version-check'], disabled: false);
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
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      errors.add(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
