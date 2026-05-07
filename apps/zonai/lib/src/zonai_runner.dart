import 'commands/compile.dart';
import 'commands/db/db.dart';
import 'commands/serve.dart';
import 'deps/args.dart';

const _usage = '''
Usage: zonai <command> [options]

Commands:
  help        Show help information
  version     Show version information
  db          Manage database
  serve       Serve the application
  compile     Compile all workers
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

  switch (args.path) {
    case ['version']:
      throw UnimplementedError();
    case ['db', ...final path]:
      return await db(path);
    case ['serve']:
      return await serve();
    case ['compile']:
      return await compile();
    default:
      print(_usage);
  }

  return 1;
}
