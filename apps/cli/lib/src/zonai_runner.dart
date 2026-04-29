import 'package:zonai/src/commands/db/db.dart';
import 'package:zonai/src/commands/serve.dart';
import 'package:zonai/src/deps/args.dart';

const _usage = '''
Usage: zonai <command> [options]

Commands:
  help        Show help information
  version     Show version information
  db          Manage database
  serve       Serve the application
''';

Future<int> run() async {
  if (args.path.isEmpty) {
    print(_usage);
    return 1;
  }

  if (args.help && args.path.isEmpty) {
    print(_usage);
    return 1;
  }

  if (args.path case ['version']) {
    print('zonai');
    return 1;
  }

  switch (args.path) {
    case ['db', ...final path]:
      return await db(path);
    case ['serve']:
      return await serve();
    default:
      print(_usage);
  }

  return 1;
}
