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

    test('--dart-define overrides a matching .env key', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          memoryFs.file('.env').writeAsStringSync('''
BASE_URL=http://localhost:8080
JWT_SECRET=dev-secret
''');

          final env = Env();

          expect(env.items['BASE_URL'], 'https://staging.example.com');
          expect(env.items['JWT_SECRET'], 'dev-secret');
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          argsProvider.overrideWith(
            () => Args.parse([
              '--dart-define',
              'BASE_URL=https://staging.example.com',
            ]),
          ),
        },
      );
    });

    test('--dart-define adds keys when no .env file exists', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          final env = Env();

          expect(env.items['FEATURE_FLAG'], 'on');
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          argsProvider.overrideWith(
            () => Args.parse(['--dart-define', 'FEATURE_FLAG=on']),
          ),
        },
      );
    });

    test('repeated --dart-define flags are all applied', () {
      final memoryFs = MemoryFileSystem();

      runScoped(
        () {
          final env = Env();

          expect(env.items['A'], '1');
          expect(env.items['B'], '2');
        },
        values: {
          fsProvider.overrideWith(() => memoryFs),
          argsProvider.overrideWith(
            () => Args.parse(['--dart-define', 'A=1', '--dart-define', 'B=2']),
          ),
        },
      );
    });
  });
}
