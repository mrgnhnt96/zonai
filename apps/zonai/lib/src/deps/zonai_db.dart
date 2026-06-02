import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/keyboard_input.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/domain/constants.dart';
import '../db_mutator/zonai_db/zonai_db.dart';

ZonaiDb? _db;

final zonaiDbProvider = create<ZonaiDb Function()>(
  () => () {
    if (!kIsCompiled) {
      if (isRegistered(keyboardInputProvider)) {
        keyboardInput.onKey('r', () {
          logger.info('Restarting Zonai DB');
          _db?.dispose();
          _db = null;
        });
      }
    }

    return _db ??= ZonaiDb();
  },
);

ZonaiDb get zonaiDB => read(zonaiDbProvider)();
