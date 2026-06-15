import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/env.dart';
import 'package:zonai/src/utils/args.dart';

void main() {
  group(parseEnvValue, () {
    test('strips double quotes', () {
      expect(parseEnvValue('"hello world"'), 'hello world');
    });

    test('strips single quotes', () {
      expect(parseEnvValue("'hello world'"), 'hello world');
    });

    test('leaves unquoted values unchanged', () {
      expect(parseEnvValue('hello world'), 'hello world');
    });

    test('leaves mismatched quotes unchanged', () {
      expect(parseEnvValue('"mismatch\''), '"mismatch\'');
    });
  });

  group('Env.items', () {
    test('strips quotes from .env values', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.file('.env').writeAsStringSync('''
GMAIL_APP_PASSWORD="yafs dkvu wbfb lpmf"
SINGLE='single quoted'
PLAIN=plain
''');

          final env = Env();

          expect(env.items['GMAIL_APP_PASSWORD'], 'yafs dkvu wbfb lpmf');
          expect(env.items['SINGLE'], 'single quoted');
          expect(env.items['PLAIN'], 'plain');
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          argsProvider.overrideWith(() => const Args()),
        },
      );
    });
  });
}
