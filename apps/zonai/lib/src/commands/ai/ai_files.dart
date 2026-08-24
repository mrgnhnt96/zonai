import '../../domain/ai_docs.dart';
import 'ai_templates.dart';

/// Every file `zonai ai` installs: tool -> path -> contents.
///
/// The paths come from [aiDocPaths] so the installers and the staleness scan
/// cannot name different files; `ai_docs_paths_test.dart` pins the cursor
/// entries against [cursorMdcFiles] in both directions, since that is the one
/// pairing a typo could silently drop.
final aiToolFiles = <String, Map<String, String>>{
  'claude': {aiDocPaths['claude']!.single: claudeMd},
  'cursor': {
    for (final entry in cursorMdcFiles.entries)
      '.cursor/rules/${entry.key}': entry.value,
  },
  'copilot': {aiDocPaths['copilot']!.single: copilotMd},
  'windsurf': {aiDocPaths['windsurf']!.single: windsurfRules},
  'cline': {aiDocPaths['cline']!.single: clineRules},
};
