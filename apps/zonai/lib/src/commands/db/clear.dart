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

/// Asks [question] on stdout and returns whether the answer was affirmative.
bool _confirmViaStdin(String question) {
  stdout.write(question);
  final line = stdin.readLineSync()?.trim().toLowerCase();
  return line == 'y' || line == 'yes';
}

Future<int> clearDatabase({bool Function(String question)? confirm}) async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final dbFile = fs.file(settings.zonaiSqlitePath);
  // The log database is a second file (see `Settings.zonaiLogSqlitePath`).
  // Leaving it behind would make `db clear` look like it cleared the
  // database while every log record survived into the next open.
  final logDbFile = fs.file(settings.zonaiLogSqlitePath);
  final targets = [
    for (final file in [dbFile, logDbFile]) ...[
      file,
      fs.file('${file.path}-wal'),
      fs.file('${file.path}-shm'),
    ],
  ].where((f) => f.existsSync()).toList();

  if (targets.isEmpty) {
    logger.info('No database file found at ${dbFile.path}');
    return 0;
  }

  // Read through `getOrNull` with the abbreviation declared: `-y` is parsed
  // into `abbrs`, not `values`, so `args['y']` never saw it and the
  // documented short form prompted anyway.
  if (args.getOrNull<bool>('yes', abbr: 'y') != true) {
    final answered = (confirm ?? _confirmViaStdin)(
      'Delete ${dbFile.path}? [y/N]: ',
    );

    if (!answered) {
      logger.info('Cancelled.');
      return 0;
    }
  }

  await zonaiDB.dispose();

  for (final file in targets) {
    file.deleteSync();
    logger.info('Deleted ${file.path}');
  }

  return 0;
}
