import 'dart:async';

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
import '../db_mutator/mailman.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/src/handlers/config/config_request.dart';
import 'package:zonai_schema/src/handlers/config/config_response.dart';

Future<int> serve() async {
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

  final extensionMailman = Mailman<ExtensionRequest, ExtensionResponse>(
    debugName: 'EXTENSIONS',
    executablePath: extensions.executablePath,
    fromJson: ExtensionResponse.fromJson,
  );

  final rulesMailman = Mailman<RuleRequest, RuleResponse>(
    debugName: 'RULES',
    executablePath: rules.executablePath,
    fromJson: RuleResponse.fromJson,
  );

  final operationMailman = Mailman<OperationRequest, OperationResponse>(
    debugName: 'OPERATIONS',
    executablePath: operations.executablePath,
    fromJson: OperationResponse.fromJson,
  );

  final configMailman = Mailman<ConfigRequest, ConfigResponse>(
    debugName: 'CONFIG',
    executablePath: config.executablePath,
    fromJson: ConfigResponse.fromJson,
  );

  keyboardInput.addListener((event) {
    final print = (bool success, String name) {
      logger.info('Ping $name ${success ? 'succeeded' : 'failed'}');
    };

    if (event.matches('p')) {
      extensionMailman.ping().then((s) => print(s, 'extension'));
      rulesMailman.ping().then((s) => print(s, 'rules'));
      operationMailman.ping().then((s) => print(s, 'operation'));
      configMailman.ping().then((s) => print(s, 'config'));
    }
  });

  await kill.wait();

  return 0;
}
