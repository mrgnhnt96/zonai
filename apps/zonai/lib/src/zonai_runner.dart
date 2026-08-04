import 'package:zonai/src/commands/build.dart';
import 'package:zonai/src/commands/version.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/raindrop_sync.dart';
import 'package:zonai/src/deps/versions.dart';
import 'package:zonai/src/domain/project/project_runtime.dart';

import 'commands/ai/ai.dart';
import 'commands/compile.dart';
import 'commands/db/db.dart';
import 'commands/dev/dev.dart';
import 'commands/ping.dart';
import 'commands/raindrop.dart';
import 'commands/rules.dart';
import 'commands/serve.dart';
import 'deps/args.dart';

const _usage = '''
Usage: zonai <command> [options]

Commands:
  help        Show help information
  version     Show version information
  build       Build the application for deployment
  db          Manage database
  dev         Interactive development TUI
  serve       Serve the application
  compile     Compile all workers
  ping        Ping worker executables
  rules       Inspect compiled rules
  raindrop    Manage the embedded raindrop bundle
  ai          Install AI coding assistant reference files
''';

Future<int> run() async {
  if (args.path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  if (await versions.assertVersion() case final exitCode?) {
    return exitCode;
  }

  final isExplicitVersionCommand = switch (args.path) {
    ['version', 'update' || 'check', ...] => true,
    _ => false,
  };

  if (!isExplicitVersionCommand) {
    await versions.checkForUpdate();
  }

  if (args.help && args.path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  await raindropSync.ensure();

  if (await maybeReexecProjectRuntime() case final exitCode?) {
    return exitCode;
  }

  switch (args.path) {
    case ['version', ...final path]:
      return await version(path);
    case ['build']:
      return await build();
    case ['db', ...final path]:
      return await db(path);
    case ['dev']:
      return await dev();
    case ['serve']:
      return await serve();
    case ['compile']:
      return await compile();
    case ['ping']:
      return await ping();
    case ['rules', ...final path]:
      return await rules(path);
    case ['raindrop', ...final path]:
      return await raindrop(path);
    case ['ai', ...final path]:
      return await ai(path);
    default:
      logger.info(_usage);
  }

  return 1;
}
