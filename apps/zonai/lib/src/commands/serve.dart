import 'dart:async';

import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/messengers/config_mailman.dart';
import 'package:zonai/src/messengers/cron_mailman.dart';
import 'package:zonai/src/messengers/extensions_mailman.dart';
import 'package:zonai/src/messengers/operations_mailman.dart';
import 'package:zonai/src/messengers/rules_mailman.dart';
import 'package:zonai/src/utils/serve_guard.dart';

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

Future<int> serve() async {
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

  logger.info('serving');

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
