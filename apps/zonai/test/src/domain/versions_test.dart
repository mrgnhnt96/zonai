import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/domain/ai_docs.dart';
import 'package:zonai/src/domain/versions.dart';
import 'package:zonai_logger/zonai_logger.dart';

void main() {
  group('isBreakingCliUpgrade', () {
    test('is false for the same version', () {
      expect(isBreakingCliUpgrade(from: '1.2.3', to: '1.2.3'), isFalse);
    });

    test('is false for a patch bump within the same >= 1.0 major', () {
      expect(isBreakingCliUpgrade(from: '1.2.3', to: '1.2.4'), isFalse);
    });

    test('is false for a minor bump within the same >= 1.0 major', () {
      expect(isBreakingCliUpgrade(from: '1.2.3', to: '1.3.0'), isFalse);
    });

    test('is true for a major bump', () {
      expect(isBreakingCliUpgrade(from: '1.9.0', to: '2.0.0'), isTrue);
    });

    test('is false for a patch bump within the same 0.x minor', () {
      expect(isBreakingCliUpgrade(from: '0.6.0', to: '0.6.3'), isFalse);
    });

    test(
      'is true for a minor bump below 1.0, since minor is the breaking slot',
      () {
        expect(isBreakingCliUpgrade(from: '0.6.0', to: '0.7.0'), isTrue);
      },
    );

    test('is true for a downgrade that crosses the same boundary', () {
      expect(isBreakingCliUpgrade(from: '0.7.0', to: '0.6.0'), isTrue);
    });
  });

  group('offerAiDocRefresh', () {
    // The AI reference sheets describe the CLI, so an update leaves whatever
    // the project has committed describing the release it just left. Nothing
    // said so before: `zonai ai` skipped the existing file and reported only
    // "Skipped".
    test('says nothing when the project has no reference files', () async {
      final output = await _refresh(MemoryFileSystem(), '9.9.9');

      expect(output, isEmpty);
    });

    test(
      'says nothing when every file already names the new version',
      () async {
        final fs = MemoryFileSystem();
        fs
            .file('CLAUDE.md')
            .writeAsStringSync(stampAiDoc('a', version: '9.9.9'));

        expect(await _refresh(fs, '9.9.9'), isEmpty);
      },
    );

    test('names each stale file and how it is stale', () async {
      final fs = MemoryFileSystem();
      fs.file('CLAUDE.md').writeAsStringSync(stampAiDoc('a', version: '0.7.0'));
      fs.file('.clinerules').writeAsStringSync('written before stamping');

      final output = await _refresh(fs, '9.9.9');

      expect(output, contains('2 AI reference file(s)'));
      expect(output, contains('CLAUDE.md (written by v0.7.0)'));
      expect(output, contains('.clinerules (no version stamp)'));
    });

    test('points at zonai ai update when it cannot run the new binary', () async {
      // Running from source there is no installed executable to re-run, and on
      // Windows the swap is deferred to exit -- `Platform.executable` is still
      // the outgoing binary, whose templates are the stale ones.
      final fs = MemoryFileSystem();
      fs.file('.windsurfrules').writeAsStringSync('unstamped');

      expect(await _refresh(fs, '9.9.9'), contains('zonai ai update'));
    });
  });
}

/// Runs the post-update offer against [fs] and returns everything it logged.
Future<String> _refresh(MemoryFileSystem fs, String targetVersion) async {
  final output = StringBuffer();
  final sink = CallbackSink(callback: output.write);

  await runScoped(
    () => const Versions().offerAiDocRefresh(targetVersion),
    values: {
      fsProvider.overrideWith(() => fs),
      loggerProvider.overrideWith(() => Logger(stdout: sink, stderr: sink)),
    },
  );

  return output.toString();
}
