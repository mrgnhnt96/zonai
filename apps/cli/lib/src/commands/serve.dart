import 'dart:async';

import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/domain/migrate.dart';

Future<int> serve() async {
  if (args['auto-migrate'] case true || null) {
    Migrate().auto();
  }

  print('serving');
  return 0;
}
