import 'dart:io';

import 'package:clock/clock.dart';

import '../../../deps/args.dart';
import '../../../deps/fs.dart';
import '../../../deps/logger.dart';
import '../../../deps/settings.dart';
import '../../../deps/zonai_db.dart';
import '../../../utils/format_bytes.dart';
import '../../../utils/parse_duration.dart';

const _usage = '''
Usage: zonai db logs clear [options]

Delete log records from the _log internal collection.

Deleting rows frees them inside the database file but does not shrink the file
on disk -- SQLite keeps the emptied pages on a freelist for reuse. Pass
--vacuum to rewrite the file and hand that space back to the operating system.

Options:
  -h, --help              Show help information
      --older-than=<age>  Only delete records older than <age>, where <age> is
                          a number followed by s, m, h, d or w (e.g. 7d, 24h)
      --vacuum            Rewrite the database file afterwards to reclaim disk
                          space. Prompts for confirmation first.
  -f, --force             Skip the --vacuum confirmation prompt
''';

/// Asks [question] on stdout and returns whether the answer was affirmative.
bool _confirmViaStdin(String question) {
  stdout.write(question);
  final line = stdin.readLineSync()?.trim().toLowerCase();
  return line == 'y' || line == 'yes';
}

/// Explains what a VACUUM is about to do before it does it.
///
/// The rewrite is slow, needs room for a second copy of the database, and
/// holds an exclusive lock throughout -- none of which is guessable from the
/// flag name, and all of which matters on the multi-hundred-megabyte databases
/// that need it most.
String _vacuumWarning({required String path, required int size}) =>
    '''
--vacuum rewrites the entire database file.

  Database   $path (${formatBytes(size)})
  Disk       ~${formatBytes(size * 2)} free is needed -- SQLite builds a
             complete copy before swapping it in
  Time       proportional to the file size; a large database can take minutes
  Locking    the database is locked for the whole rewrite, so a running server
             will block on writes until it finishes

Answering no cancels the command -- no log records are deleted either.

Continue? [y/N]: ''';

Future<int> clearLogs({bool Function(String question)? confirm}) async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  DateTime? before;
  if (args['older-than'] case final Object raw) {
    final age = parseDuration('$raw');
    if (age == null) {
      logger.error(
        'Invalid --older-than value: "$raw". Expected a number followed by '
        's, m, h, d or w (e.g. 7d).',
      );
      return 1;
    }
    before = clock.now().subtract(age);
  }

  final vacuum = args.getOrNull<bool>('vacuum') == true;
  final dbFile = fs.file(settings.zonaiSqlitePath);
  final sizeBefore = dbFile.existsSync() ? dbFile.lengthSync() : 0;

  // Read through `getOrNull` with the abbreviation declared: `-f` is parsed
  // into `abbrs`, not `values`, so `args['f']` would silently never see it.
  if (vacuum && args.getOrNull<bool>('force', abbr: 'f') != true) {
    final answered = (confirm ?? _confirmViaStdin)(
      _vacuumWarning(path: dbFile.path, size: sizeBefore),
    );

    if (!answered) {
      logger.info('Cancelled.');
      return 0;
    }
  }

  try {
    final count = await zonaiDB.clearLogs(before: before);
    logger.info('Cleared $count log record${count == 1 ? '' : 's'}');

    if (!vacuum) {
      // The whole point of issue #28: without this, `clear` looks like it
      // reclaimed the space it just reported clearing.
      if (count > 0 && sizeBefore > 0) {
        logger.info(
          '${formatBytes(sizeBefore)} is still allocated on disk -- the '
          'deleted pages are free inside the database file but were not '
          'returned to the OS. Re-run with --vacuum to reclaim them.',
        );
      }
      return 0;
    }

    await zonaiDB.vacuum();

    final sizeAfter = dbFile.existsSync() ? dbFile.lengthSync() : 0;
    logger.info(
      'Reclaimed ${formatBytes(sizeBefore - sizeAfter)} '
      '(${formatBytes(sizeBefore)} -> ${formatBytes(sizeAfter)})',
    );
    return 0;
  } catch (e, stack) {
    logger.error('Failed to clear logs: $e', e, stack);
    return 1;
  }
}
