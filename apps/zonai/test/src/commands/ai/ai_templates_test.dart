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
}
