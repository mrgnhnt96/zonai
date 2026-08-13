import 'dart:async';

import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/messengers/config_mailman.dart';
import 'package:zonai/src/messengers/cron_mailman.dart';
import 'package:zonai/src/messengers/extensions_mailman.dart';
import 'package:zonai/src/messengers/operations_mailman.dart';
import 'package:zonai/src/messengers/rules_mailman.dart';
import 'package:zonai/src/utils/serve_guard.dart';

import 'dev/actions/project_init.dart';
import '../deps/args.dart';
import '../deps/config.dart';
import '../deps/extensions.dart';
import '../deps/keyboard_input.dart';
import '../deps/kill.dart';
import '../deps/logger.dart';
import '../deps/migrate.dart';
import '../deps/operations.dart';
import '../deps/rate_limits.dart';
import '../deps/crons.dart';
import '../deps/revali.dart';
import '../deps/rules.dart';
import '../native/resqlite_native.dart';

const _usage = '''
Usage: zonai serve [options]

Start the Zonai HTTP server.

Options:
  -h, --help              Show help information
      --host=<address>    Bind address (default: zonai.yml host, then
                          localhost)
      --port=<number>     HTTP port (default: zonai.yml port, then 8080)
      --flavor=<name>     Config flavor to load
      --release           Production mode: no file watchers, no recompiling
      --no-auto-migrate   Do not apply pending migrations on startup
  -c, --config=<path>     Path to zonai.yml

Keys while serving:
  c   Recompile all workers
  m   Generate and apply database migrations
  p   Ping all workers and print their health
  r   Restart the database connection (dev only)
  q   Quit
''';

Future<int> serve() async {
  // First statement in the command, deliberately: everything after it starts
  // a server. `serve --help` on a production box used to boot a second one --
  // binding the port, sweeping crons, and auto-applying pending migrations --
  // for someone who only wanted to read the flags.
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  if (await ensureProjectInitialized() case final initExitCode?) {
    return initExitCode;
  }

  var exitCode = 0;

  await runServeGuarded(() async {
    try {
      exitCode = await _startServing();
      if (exitCode != 0) return;
    } catch (error, stack) {
      logger.error('Error while serving (process continues)', error, stack);
    }
    await kill.wait();
  });

  return exitCode;
}

void _compileWorkers() {
  catchErrors(() {
    logger.info('Compiling all workers...');
    catchErrors(operations.compile);
    catchErrors(extensions.compile);
    catchErrors(rules.compile);
    catchErrors(rateLimitsCompiler.compile);
    catchErrors(cronsCompiler.compile);
    catchErrors(config.compile);
  });
}

Future<int> _startServing() async {
  await ensureResqliteNativeInstalled();

  keyboardInput.watch();

  if (args['auto-migrate'] case != false) {
    catchErrors(migrate.auto);
  }
  migrate.listenForKeyboardInput();

  extensions.watch();
  rules.watch();
  rateLimitsCompiler.watch();
  cronsCompiler.watch();
  config.watch();
  operations.watch();
  env.watch(_compileWorkers);

  keyboardInput.onKey('c', _compileWorkers);

  if (!await revali.start()) {
    return 1;
  }

  final extensionMailman = ExtensionsMailman();
  final rulesMailman = RulesMailman();
  final operationMailman = OperationsMailman();
  final configMailman = ConfigMailman();
  final cronMailman = CronMailman()..start();

  keyboardInput.onKey('p', () {
    catchErrors(() async {
      final print = (bool success, String name) {
        logger.info('Ping $name ${success ? 'succeeded' : 'failed'}');
      };

      print(await extensionMailman.ping(), 'extension');
      print(await rulesMailman.ping(), 'rules');
      print(await operationMailman.ping(), 'operation');
      print(await configMailman.ping(), 'config');
      print(await cronMailman.ping(), 'cron');
    });
  });

  return 0;
}
