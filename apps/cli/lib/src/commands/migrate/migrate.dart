import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/domain/migrate.dart';
import 'package:zonai/src/domain/settings.dart';

part '__generate.dart';

const _usage = '''
Usage: zonai db migrate [options] [generate]

Options:
  -h, --help      Show help information
  -n, --name      Name for the migration
  --dry-run       Show what would be generated without creating files

Subcommands:
  generate        Generate SQL migrations from schema changes (optional when --name is set)
''';

/// Routes `zonai migrate` subcommands (e.g. [generate]) using [Settings] paths.
Future<int> migrate(List<String> path) async {
  if (args.help && path.isEmpty) {
    print(_usage);
    return 1;
  }

  if (path.isEmpty && args.getOrNull('name') != null) {
    return await _generate();
  }

  switch (path) {
    case ['generate' || 'g' || 'gen']:
      return await _generate();
    default:
      print(_usage);
      return 1;
  }
}
