import 'package:test/test.dart';
import 'package:zonai/src/commands/ai/ai_templates.dart';

void main() {
  test("AI reference templates don't reintroduce the raindrop import that "
      "collides with zonai_schema's vendored re-export", () {
    // zonai_schema.dart re-exports raindrop (hide table, Logger, migrate)
    // as of v0.5.2 -- importing package:raindrop/raindrop.dart alongside
    // it produces `ambiguous_import` for everything both export. These
    // templates are what `zonai ai` writes into a *user's own project*,
    // so a stale example here gets copied into real code, not just read.
    // See issue #22.
    final templates = <String, String>{
      'claudeMd': claudeMd,
      'copilotMd': copilotMd,
      'windsurfRules': windsurfRules,
      'clineRules': clineRules,
      ...cursorMdcFiles,
    };

    for (final entry in templates.entries) {
      expect(
        entry.value.contains("import 'package:raindrop/raindrop.dart'"),
        isFalse,
        reason:
            '${entry.key} should not tell readers to import raindrop '
            'alongside zonai_schema -- zonai_schema re-exports what a '
            'view file needs on its own.',
      );
    }
  });

  test('AI templates answer --dart-define-from-file, the flag zonai does '
      'not have', () {
    // An agent looking for Flutter's --dart-define-from-file finds nothing in
    // zonai and has no way to tell "absent because unsupported" from "absent
    // because undocumented" -- and the parser accepts the flag silently
    // (Args.parse keeps every --flag value pair; only `dart-define` is ever
    // read, in Env._cliDefines), so guessing it produces a clean build with
    // zero defines. The term has to appear in the templates for the answer to
    // be findable at all.
    for (final entry in {
      'claudeMd': claudeMd,
      'copilotMd': copilotMd,
      'windsurfRules': windsurfRules,
      'clineRules': clineRules,
      'zonai-overview.mdc': cursorOverviewMdc,
      'zonai-release.mdc': cursorReleaseMdc,
    }.entries) {
      expect(
        entry.value,
        contains('--dart-define-from-file'),
        reason:
            '${entry.key} documents compile-time env defines, so it has to '
            'say that --dart-define-from-file does not exist and that .env '
            'is loaded without being named.',
      );
    }
  });
}
