import 'package:zonai/src/commands/version.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/versions.dart';

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
    logger.info(_usage);
    return 1;
  }

  if (await versions.assertVersion() case final exitCode?) {
    return exitCode;
  }

  await versions.checkForUpdate();

  if (args.help && args.path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (args.path) {
    case ['version', ...final path]:
      return await version(path);
    case ['db', ...final path]:
      return await db(path);
    case ['serve']:
      return await serve();
    case ['compile']:
      return await compile();
    default:
      logger.info(_usage);
  }

  return 1;
}
