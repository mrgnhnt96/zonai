import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/src/internal/tables/logs_table.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger;

import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db logs clear [options]

Delete all log records from the _log internal collection.

Options:
  -h, --help      Show help information
''';

Future<int> clearLogs() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  try {
    final db = await zonaiDB.open();
    final result = await db
        .delete(from: logs)
        .where(RawSqlFilter('1=1'))
        .returning();

    final count = result.length;
    logger.info('Cleared $count log record${count == 1 ? '' : 's'}');
    return 0;
  } catch (e, stack) {
    logger.error('Failed to clear logs: $e', stack);
    return 1;
  }
}
