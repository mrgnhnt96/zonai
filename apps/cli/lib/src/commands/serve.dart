import 'dart:async';

import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/domain/extensions.dart';
import 'package:zonai_cli/src/domain/migrate.dart';

Future<int> serve() async {
  if (args['auto-migrate'] case true || null) {
    Migrate().auto();
  }

  Extensions().watch();

  print('serving');
  return 0;
}
