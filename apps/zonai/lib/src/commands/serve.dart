import 'dart:async';

import 'package:zonai/src/messengers/config_mailman.dart';
import 'package:zonai/src/messengers/cron_mailman.dart';
import 'package:zonai/src/messengers/extensions_mailman.dart';
import 'package:zonai/src/messengers/operations_mailman.dart';
import 'package:zonai/src/messengers/rules_mailman.dart';

import '../deps/args.dart';
import '../deps/config.dart';
import '../deps/extensions.dart';
import '../deps/keyboard_input.dart';
import '../deps/kill.dart';
import '../deps/logger.dart';
import '../deps/migrate.dart';
import '../deps/operations.dart';
import '../deps/rate_limits.dart';
import '../deps/revali.dart';
import '../deps/rules.dart';
import '../native/resqlite_native.dart';

Future<int> serve() async {
  await ensureResqliteNativeInstalled();

  keyboardInput.watch();

  if (args['auto-migrate'] case != false) {
    migrate.auto();
  }
  migrate.listenForKeyboardInput();

  extensions.watch();
  rules.watch();
  rateLimitsCompiler.watch();
  config.watch();
  operations.watch();

  keyboardInput.addListener((event) {
    if (event.matches('c')) {
      logger.info('Compiling all workers...');
      operations.compile();
      extensions.compile();
      rules.compile();
      rateLimitsCompiler.compile();
      config.compile();
    }
  });

  if (!await revali.start()) {
    return 1;
  }

  logger.info('serving');

  final extensionMailman = ExtensionsMailman();
  final rulesMailman = RulesMailman();
  final operationMailman = OperationsMailman();
  final configMailman = ConfigMailman();
  final cronMailman = CronMailman()..start();

  keyboardInput.addListener((event) {
    final print = (bool success, String name) {
      logger.info('Ping $name ${success ? 'succeeded' : 'failed'}');
    };

    if (event.matches('p')) {
      extensionMailman.ping().then((s) => print(s, 'extension'));
      rulesMailman.ping().then((s) => print(s, 'rules'));
      operationMailman.ping().then((s) => print(s, 'operation'));
      configMailman.ping().then((s) => print(s, 'config'));
      cronMailman.ping().then((s) => print(s, 'cron'));
    }
  });

  await kill.wait();

  return 0;
}
