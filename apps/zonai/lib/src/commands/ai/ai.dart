import '../../deps/args.dart';
import '../../deps/logger.dart';
import 'tools/cline.dart';
import 'tools/claude.dart';
import 'tools/copilot.dart';
import 'tools/cursor.dart';
import 'tools/windsurf.dart';

const _usage = '''
Usage: zonai ai <tool> [options]

Install AI coding assistant reference files into your project.
Files are skipped if they already exist (use --force to overwrite).

Tools:
  all        Install files for all supported tools
  claude     Claude Code (CLAUDE.md)
  cursor     Cursor (.cursor/rules/zonai-*.mdc)
  copilot    GitHub Copilot (.github/copilot-instructions.md)
  windsurf   Windsurf (.windsurfrules)
  cline      Cline (.clinerules)

Options:
  -f, --force  Overwrite existing files
  -h, --help   Show this help
''';

Future<int> ai(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['claude']:
      return await installClaude();
    case ['cursor']:
      return await installCursor();
    case ['copilot']:
      return await installCopilot();
    case ['windsurf']:
      return await installWindsurf();
    case ['cline']:
      return await installCline();
    case ['all']:
      await installClaude();
      await installCursor();
      await installCopilot();
      await installWindsurf();
      await installCline();
      return 0;
    default:
      logger.info(_usage);
      return 1;
  }
}
