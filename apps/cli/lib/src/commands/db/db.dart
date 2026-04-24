import 'package:zonai_cli/src/commands/db/update.dart';
import 'package:zonai_cli/src/commands/migrate/migrate.dart';
import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/logger.dart';

const _usage = '''
Usage: zonai db [options]

Options:
  -h, --help      Show help information

Subcommands:
  migrate         Manage SQL migrations

Commands:
  help            Show help information
''';

Future<int> db(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['migrate' || 'migrations' || 'm' || 'migration', ...final path]:
      return await migrate(path);

    case ['update', ...final path]:
      return await update(path);
    default:
      logger.info(_usage);
      return 1;
  }
}
