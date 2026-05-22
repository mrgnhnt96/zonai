import 'admin.dart';
import 'logs.dart';
import 'test.dart';
import '../migrate/migrate.dart';
import '../../deps/args.dart';
import '../../deps/logger.dart';

const _usage = '''
Usage: zonai db [options]

Options:
  -h, --help      Show help information

Subcommands:
  migrate         Manage SQL migrations
  admin           Manage admin accounts
  logs            Manage internal log records

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

    case ['test']:
      return await test();

    case ['admin', ...final path]:
      return await admin(path);

    case ['logs' || 'log', ...final path]:
      return await logs(path);

    default:
      logger.info(_usage);
      return 1;
  }
}
