import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/domain/target_os.dart';

void main() {
  group('Settings.load', () {
    test('defaults imagesPath to dataPath/images', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.file('zonai.yaml').writeAsStringSync('version: 0.1.0\n');

          final settings = Settings.load();

          expect(settings.dataPath, '.zonai/data');
          expect(settings.imagesPath, '.zonai/data/images');
        },
        values: {fsProvider.overrideWith(() => memoryFs)},
      );
    });

    test('derives imagesPath from custom dataPath', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.file('zonai.yaml').writeAsStringSync('''
version: 0.1.0
dataPath: custom/data
''');

          final settings = Settings.load();

          expect(settings.dataPath, 'custom/data');
          expect(settings.imagesPath, 'custom/data/images');
        },
        values: {fsProvider.overrideWith(() => memoryFs)},
      );
    });

    test('allows imagesPath override', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.file('zonai.yaml').writeAsStringSync('''
version: 0.1.0
imagesPath: uploads/photos
''');

          final settings = Settings.load();

          expect(settings.dataPath, '.zonai/data');
          expect(settings.imagesPath, 'uploads/photos');
        },
        values: {fsProvider.overrideWith(() => memoryFs)},
      );
    });

    test('derives buildImagesPath from imagesPath', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.file('zonai.yaml').writeAsStringSync('version: 0.1.0\n');

          final settings = Settings.load();

          expect(settings.buildImagesPath, 'build/.zonai/data/images');
        },
        values: {fsProvider.overrideWith(() => memoryFs)},
      );
    });

    test('loads dartSdkPath from zonai.yaml', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.file('zonai.yaml').writeAsStringSync('''
version: 0.1.0
dartSdkPath: /opt/dart-sdk
''');

          final settings = Settings.load();

          expect(settings.dartSdkPath, '/opt/dart-sdk');
        },
        values: {fsProvider.overrideWith(() => memoryFs)},
      );
    });
  });

  /// The flag names are the whole content of this getter, and they are what
  /// `dart compile` actually accepts -- probed against Dart 3.12 on macOS
  /// arm64, for `aot-snapshot` specifically, since that is the subcommand that
  /// was missing them:
  ///
  ///   dart compile aot-snapshot main.dart              -> Mach-O ... arm64
  ///   dart compile aot-snapshot --target-os linux \
  ///     --target-arch x64 main.dart                    -> ELF ... x86-64
  ///
  /// So the flags are honoured by `aot-snapshot` and not merely tolerated,
  /// which is what the callers depend on.
  ///
  /// The asymmetry these lock down is checked for real by
  /// tool/ci/cross_target_build.sh, which reads the header of every object file
  /// in a cross-built bundle. That runs only in the release workflows, so this
  /// is the part that runs on every commit.
  group('BuildSettings.compileTargetArgs', () {
    test('names the target for dart compile', () {
      final settings = BuildSettings(
        targetOs: TargetOs.linux,
        targetArch: Arch.x64,
      );

      expect(settings.compileTargetArgs, [
        '--target-os',
        'linux',
        '--target-arch',
        'x64',
      ]);
    });

    test('spreads to nothing when there is no build target', () {
      const BuildSettings? absent = null;

      expect([...?absent?.compileTargetArgs], isEmpty);
    });
  });
}
