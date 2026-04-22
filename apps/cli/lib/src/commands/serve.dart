import 'dart:async';

import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/extensions.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/kill.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/migrate.dart';
import 'package:zonai_cli/src/deps/operations.dart';
import 'package:zonai_cli/src/deps/revali.dart';
import 'package:zonai_cli/src/deps/rules.dart';
import 'package:zonai_cli/src/db_mutator/mailman.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';

Future<int> serve() async {
  keyboardInput.watch();

  if (args['auto-migrate'] case != false) {
    migrate.auto();
  }
  migrate.listenForKeyboardInput();

  extensions
    ..watch()
    ..listenForKeyboardInput();
  rules
    ..watch()
    ..listenForKeyboardInput();

  operations
    ..watch()
    ..listenForKeyboardInput();

  keyboardInput.addListener((event) {
    if (event.matches('c')) {
      logger.info('Compiling all workers...');
      operations.compile();
      extensions.compile();
      rules.compile();
    }
  });

  if (!await revali.start()) {
    return 1;
  }

  logger.info('serving');

  final extensionMailman = Mailman<ExtensionRequest, ExtensionResponse>(
    executablePath: extensions.executablePath,
    fromJson: ExtensionResponse.fromJson,
  );

  final rulesMailman = Mailman<RuleRequest, RuleResponse>(
    executablePath: rules.executablePath,
    fromJson: RuleResponse.fromJson,
  );

  final operationMailman = Mailman<OperationRequest, OperationResponse>(
    executablePath: operations.executablePath,
    fromJson: OperationResponse.fromJson,
  );

  keyboardInput.addListener((event) {
    final print = (bool success, String name) {
      logger.info('Ping $name ${success ? 'succeeded' : 'failed'}');
    };

    if (event.matches('p')) {
      extensionMailman.ping().then((s) => print(s, 'extension'));
      rulesMailman.ping().then((s) => print(s, 'rules'));
      operationMailman.ping().then((s) => print(s, 'operation'));
    }
  });

  await kill.wait();

  return 0;
}
