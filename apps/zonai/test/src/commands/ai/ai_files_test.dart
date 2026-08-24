import 'package:test/test.dart';
import 'package:zonai/src/commands/ai/ai_files.dart';
import 'package:zonai/src/commands/ai/ai_templates.dart';
import 'package:zonai/src/domain/ai_docs.dart';

/// Two lists name the same files: `aiDocPaths` (what a scan looks for, in the
/// domain, which cannot import a template) and `aiToolFiles` (what the
/// installers write). A file present in one and missing from the other is
/// silent in both directions -- an installed sheet nothing ever reports as
/// stale, or a path reported stale that `zonai ai update` then refuses to
/// rewrite, leaving the prompt to fire on every future update.
void main() {
  test('every tool that installs files is scannable, and vice versa', () {
    expect(aiToolFiles.keys.toSet(), aiDocPaths.keys.toSet());
  });

  test('each tool writes exactly the paths a scan looks for', () {
    for (final tool in aiToolFiles.keys) {
      expect(
        aiToolFiles[tool]!.keys.toSet(),
        aiDocPaths[tool]!.toSet(),
        reason: '$tool installs different files than aiDocPaths lists',
      );
    }
  });

  test('the cursor rule files stay pinned to the templates that back them', () {
    // The nine-way pairing is the one a typo could drop quietly: the .mdc
    // names live in `cursorMdcFiles`, the paths in `aiDocPaths`.
    expect(
      cursorMdcFiles.keys.map((name) => '.cursor/rules/$name').toSet(),
      aiDocPaths['cursor']!.toSet(),
    );
  });

  test('no path is claimed by two tools', () {
    final paths = allAiDocPaths.toList();
    expect(paths.toSet(), hasLength(paths.length));
  });

  test('every installed file has contents', () {
    for (final entry in aiToolFiles.values.expand((f) => f.entries)) {
      expect(entry.value, isNotEmpty, reason: '${entry.key} is empty');
    }
  });
}
