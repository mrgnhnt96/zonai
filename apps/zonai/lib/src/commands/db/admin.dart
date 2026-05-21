import '../../deps/args.dart';
import '../../deps/logger.dart';
import 'admin/add.dart';

const _usage = '''
Usage: zonai db admin [options] <subcommand>

Options:
  -h, --help      Show help information

Subcommands:
  add             Create a new admin account
''';

Future<int> admin(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['add' || 'create' || 'new']:
      return await addAdmin();
    default:
      logger.info(_usage);
      return 1;
  }
}
