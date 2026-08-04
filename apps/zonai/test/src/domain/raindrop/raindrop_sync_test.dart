import 'dart:io' as io;

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/internal/raindrop/raindrop_bundle.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/process.dart';
import 'package:zonai/src/domain/raindrop/raindrop_sync.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

class _FakeProcess extends Process {
  int pubGetCalls = 0;

  @override
  Future<io.ProcessResult> runDart(List<String> arguments) async {
    if (arguments case ['pub', 'get']) {
      pubGetCalls++;
    }
    return io.ProcessResult(0, 0, '', '');
  }
}

void main() {
  group('RaindropSync.syncNow', () {
    late MemoryFileSystem memoryFs;
    late _FakeProcess fakeProcess;

    Set<ScopedRef<dynamic>> overrides() => {
      fsProvider.overrideWith(() => memoryFs),
      argsProvider.overrideWith(() => const Args()),
      loggerProvider.overrideWith(() => Logger(level: .error)),
      processProvider.overrideWith(() => fakeProcess),
      settingsProvider.overrideWith(Settings.load),
    };

    setUp(() {
      memoryFs = MemoryFileSystem();
      fakeProcess = _FakeProcess();
    });

    test('materializes every embedded file and writes a matching stamp', () {
      return runScoped(() async {
        await const RaindropSync().syncNow();

        for (final entry in raindropBundleFiles.entries) {
          final file = fs.file(fs.path.join('.zonai/internal', entry.key));
          expect(file.existsSync(), isTrue, reason: entry.key);
          expect(file.readAsStringSync(), entry.value, reason: entry.key);
        }

        final stamp = const RaindropSync().readStamp();
        expect(stamp, isNotNull);
        expect(stamp!.hash, kRaindropBundleHash);
        expect(stamp.overrides, {
          'raindrop': '.zonai/internal/raindrop',
          'raindrop_sqlite': '.zonai/internal/raindrop_sqlite',
        });
      }, values: overrides());
    });

    test('writes dependency_overrides pointing at the materialized paths', () {
      return runScoped(() async {
        await const RaindropSync().syncNow();

        final overridesFile = fs.file('pubspec_overrides.yaml');
        expect(overridesFile.existsSync(), isTrue);
        final content = overridesFile.readAsStringSync();
        expect(content, contains('.zonai/internal/raindrop'));
        expect(content, contains('.zonai/internal/raindrop_sqlite'));
      }, values: overrides());
    });

    test('does not run `dart pub get` when pubspec.yaml is absent', () {
      return runScoped(() async {
        await const RaindropSync().syncNow();
        expect(fakeProcess.pubGetCalls, 0);
      }, values: overrides());
    });

    test('runs `dart pub get` once when pubspec.yaml exists and something changed', () {
      return runScoped(() async {
        fs.file('pubspec.yaml').writeAsStringSync('name: some_project\n');

        await const RaindropSync().syncNow();

        expect(fakeProcess.pubGetCalls, 1);
      }, values: overrides());
    });

    test('a second, unforced sync at the same bundle hash is a no-op', () {
      return runScoped(() async {
        fs.file('pubspec.yaml').writeAsStringSync('name: some_project\n');

        await const RaindropSync().syncNow();
        expect(fakeProcess.pubGetCalls, 1);

        await const RaindropSync().syncNow();
        expect(fakeProcess.pubGetCalls, 1, reason: 'fast path should skip re-sync entirely');
      }, values: overrides());
    });

    test('a forced re-sync with nothing actually changed still skips `dart pub get`', () {
      return runScoped(() async {
        fs.file('pubspec.yaml').writeAsStringSync('name: some_project\n');

        await const RaindropSync().syncNow();
        expect(fakeProcess.pubGetCalls, 1);

        await const RaindropSync().syncNow(force: true);
        expect(
          fakeProcess.pubGetCalls,
          1,
          reason: 'bundle hash and overrides are both already correct',
        );
      }, values: overrides());
    });

    test('leaves a foreign raindrop override untouched but still applies raindrop_sqlite', () {
      return runScoped(() async {
        fs.file('pubspec_overrides.yaml').writeAsStringSync('''
dependency_overrides:
  raindrop:
    path: /Users/dev/checkout/raindrop
''');

        await const RaindropSync().syncNow();

        final content = fs.file('pubspec_overrides.yaml').readAsStringSync();
        expect(content, contains('/Users/dev/checkout/raindrop'));
        expect(content, contains('.zonai/internal/raindrop_sqlite'));

        final stamp = const RaindropSync().readStamp();
        expect(stamp!.overrides, {'raindrop_sqlite': '.zonai/internal/raindrop_sqlite'});
      }, values: overrides());
    });
  });
}
