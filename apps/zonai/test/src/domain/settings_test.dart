import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/settings.dart';

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
  });
}
