import '../../deps/args.dart';
import '../../deps/logger.dart';
import 'logs/clear.dart';

const _usage = '''
Usage: zonai db logs [options] <subcommand>

Options:
  -h, --help      Show help information

Subcommands:
  clear           Delete log records, optionally reclaiming their disk space
''';

Future<int> logs(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['clear' || 'delete' || 'rm']:
      return await clearLogs();
    default:
      logger.info(_usage);
      return 1;
  }
}
