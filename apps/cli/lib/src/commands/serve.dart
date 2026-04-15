import 'dart:async';

import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/extensions.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/migrate.dart';
import 'package:zonai_cli/src/deps/operations.dart';
import 'package:zonai_cli/src/deps/rules.dart';

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

  print('serving');
  return 0;
}
