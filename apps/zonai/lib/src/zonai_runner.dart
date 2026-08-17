import 'package:zonai/src/commands/build.dart';
import 'package:zonai/src/commands/version.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/schema_version_check.dart';
import 'package:zonai/src/deps/versions.dart';
import 'package:zonai/src/domain/project/project_runtime.dart';

import 'commands/ai/ai.dart';
import 'commands/compile.dart';
import 'commands/db/db.dart';
import 'commands/dev/dev.dart';
import 'commands/gen/gen.dart';
import 'commands/ping.dart';
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
  gen         Generate code from the schema (typed client)
  ai          Install AI coding assistant reference files

Global options (accepted by every command):
  -h, --help                 Show help information
  -c, --config=<path>        Path to zonai.yml (auto-detected when omitted)
      --flavor=<name>        Config flavor to compile and load
      --release              Production mode: no asserts, no file watchers
      --log=<level>          verbose, trace, request, debug, info, warning
                             or error (default: info)
  -q, --quiet                Only print errors (same as --log error)
  -L, --loud                 Print every internal log (same as --log verbose)
      --no-version-check     Skip the CLI/project version check
      --no-schema-version-check
                             Skip the zonai_schema minimum-version check

Run `zonai <command> --help` for a command's own options.
''';

Future<int> run() async {
  if (args.path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  // `--help` must reach its command without anything happening on the way.
  //
  // Every step below can prompt, download a release, hit the network, write
  // generated sources, compile a project binary, or re-exec into one -- all
  // so the child process can print a usage string and exit. Asking a command
  // how to use it is the one invocation guaranteed to have no side effects.
  if (!args.help) {
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

    if (await schemaVersionCheck.ensure() case final exitCode?) {
      return exitCode;
    }

    if (await maybeReexecProjectRuntime() case final exitCode?) {
      return exitCode;
    }
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
    case ['gen', ...final path]:
      return await gen(path);
    case ['ai', ...final path]:
      return await ai(path);
    default:
      logger.info(_usage);
  }

  return 1;
}
