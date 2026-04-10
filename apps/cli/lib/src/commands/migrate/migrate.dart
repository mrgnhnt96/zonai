import 'package:raindrop_cli/src/cli/cli_runner.dart';
import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/domain/settings.dart';

part '__generate.dart';

const _usage = '''
Usage: zonai migrate [options]

Options:
  -h, --help      Show help information

Subcommands:
  generate        Generate SQL migrations from schema changes
''';

/// Routes `zonai migrate` subcommands (e.g. [generate]) using [Settings] paths.
Future<int> migrate(List<String> path) async {
  if (args.help && path.isEmpty) {
    print(_usage);
    return 1;
  }

  switch (path) {
    case ['generate' || 'g' || 'gen']:
      return await _generate();
    default:
      print(_usage);
  }

  return 1;
}
