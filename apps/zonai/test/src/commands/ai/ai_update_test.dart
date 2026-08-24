import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/commands/ai/ai_update.dart';
import 'package:zonai/src/commands/ai/ai_writer.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/ai_docs.dart';
import 'package:zonai/src/utils/args.dart';

void main() {
  group('writeAiFile', () {
    test('stamps what it writes with the running version', () async {
      final fs = MemoryFileSystem();

      await _run(fs, () async => writeAiFile('CLAUDE.md', '# Zonai'));

      final contents = fs.file('CLAUDE.md').readAsStringSync();
      expect(readAiDocVersion(contents), kVersion);
      expect(contents, startsWith('# Zonai'));
    });

    test('creates parent directories for nested paths', () async {
      final fs = MemoryFileSystem();

      await _run(
        fs,
        () async => writeAiFile('.cursor/rules/zonai-overview.mdc', '# R'),
      );

      expect(fs.file('.cursor/rules/zonai-overview.mdc').existsSync(), isTrue);
    });

    test('leaves an existing file alone without --force', () async {
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync('mine');

      await _run(fs, () async => writeAiFile('CLAUDE.md', '# Zonai'));

      expect(fs.file('CLAUDE.md').readAsStringSync(), 'mine');
    });

    test('overwrites when the caller has already decided', () async {
      // `zonai ai update` refreshes files it just confirmed are installed,
      // which is not the same request as --force's "install over anything".
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync('old');

      await _run(
        fs,
        () async => writeAiFile('CLAUDE.md', '# Zonai', force: true),
      );

      expect(fs.file('CLAUDE.md').readAsStringSync(), startsWith('# Zonai'));
    });

    test('overwrites when --force is passed', () async {
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync('old');

      await _run(
        fs,
        () async => writeAiFile('CLAUDE.md', '# Zonai'),
        args: ['--force'],
      );

      expect(
        readAiDocVersion(fs.file('CLAUDE.md').readAsStringSync()),
        kVersion,
      );
    });
  });

  group('zonai ai update', () {
    test('rewrites a stale file in place', () async {
      final fs = MemoryFileSystem();
      fs
          .file('CLAUDE.md')
          .writeAsStringSync(stampAiDoc('ancient', version: '0.0.1'));

      final code = await _run(fs, updateInstalledAiFiles);

      expect(code, 0);
      final contents = fs.file('CLAUDE.md').readAsStringSync();
      expect(readAiDocVersion(contents), kVersion);
      expect(contents, isNot(contains('ancient')));
    });

    test('does not install files for a tool the project never chose', () async {
      // The reason this is not `ai all --force`: refreshing one stale sheet
      // must not drop .windsurfrules, .clinerules and nine .cursor rule files
      // into a project that only ever ran `zonai ai claude`.
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync('unstamped');

      await _run(fs, updateInstalledAiFiles);

      for (final path in allAiDocPaths.where((p) => p != 'CLAUDE.md')) {
        expect(fs.file(path).existsSync(), isFalse, reason: 'created $path');
      }
    });

    test('refreshes a partial cursor install without completing it', () async {
      final fs = MemoryFileSystem();
      fs.file('.cursor/rules/zonai-rules.mdc')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old');

      await _run(fs, updateInstalledAiFiles);

      expect(
        readAiDocVersion(
          fs.file('.cursor/rules/zonai-rules.mdc').readAsStringSync(),
        ),
        kVersion,
      );
      expect(fs.file('.cursor/rules/zonai-crons.mdc').existsSync(), isFalse);
    });

    test('creates nothing in a project that never ran zonai ai', () async {
      final fs = MemoryFileSystem();

      expect(await _run(fs, updateInstalledAiFiles), 0);
      for (final path in allAiDocPaths) {
        expect(fs.file(path).existsSync(), isFalse);
      }
    });

    test('leaves nothing stale behind it', () async {
      final fs = MemoryFileSystem();
      for (final path in allAiDocPaths) {
        fs.file(path)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('unstamped');
      }

      await _run(fs, updateInstalledAiFiles);

      expect(_run(fs, () async => staleAiDocs()), completion(isEmpty));
    });
  });
}

Future<T> _run<T>(
  MemoryFileSystem fs,
  Future<T> Function() body, {
  List<String> args = const [],
}) {
  return runScoped(
    body,
    values: {
      fsProvider.overrideWith(() => fs),
      argsProvider.overrideWith(() => Args.parse(args)),
    },
  );
}
