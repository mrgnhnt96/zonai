import 'dart:io';

import '../../deps/args.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/settings.dart';
import '../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db clear [options]

Delete the local SQLite database file and WAL sidecars.

Options:
  -h, --help      Show help information
  -y, --yes       Skip confirmation prompt
''';

Future<int> clearDatabase() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final dbFile = fs.file(settings.zonaiSqlitePath);
  final targets = [
    dbFile,
    fs.file('${dbFile.path}-wal'),
    fs.file('${dbFile.path}-shm'),
  ].where((f) => f.existsSync()).toList();

  if (targets.isEmpty) {
    logger.info('No database file found at ${dbFile.path}');
    return 0;
  }

  if (args['yes'] != true && args['y'] != true) {
    stdout.write('Delete ${dbFile.path}? [y/N]: ');
    final line = stdin.readLineSync()?.trim().toLowerCase();
    if (line != 'y' && line != 'yes') {
      logger.info('Cancelled.');
      return 0;
    }
  }

  zonaiDB.dispose();

  for (final file in targets) {
    file.deleteSync();
    logger.info('Deleted ${file.path}');
  }

  return 0;
}
