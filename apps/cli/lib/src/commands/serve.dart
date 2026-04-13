import 'dart:async';

import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/extensions.dart';
import 'package:zonai_cli/src/deps/migrate.dart';
import 'package:zonai_cli/src/deps/rules.dart';

Future<int> serve() async {
  if (args['auto-migrate'] case true || null) {
    migrate.auto();
  }

  extensions.watch();
  rules.watch();

  print('serving');
  return 0;
}
