import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db admin list [options]

List every admin account. Never prints the password hash.

Options:
  -h, --help          Show help information
''';

Future<int> listAdmins() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  try {
    final admins = await zonaiDB.listAdmins();

    if (admins.isEmpty) {
      logger.info('No admin accounts found');
      return 0;
    }

    logger.info('${admins.length} admin account(s):');
    for (final admin in admins) {
      logger.info('');
      logger.info('  id: ${admin['id']}');
      logger.info('  email: ${admin['email']}');
      for (final entry in admin.entries) {
        if (entry.key == 'id' ||
            entry.key == 'email' ||
            entry.key == 'password') {
          continue;
        }
        logger.info('  ${entry.key}: ${entry.value}');
      }
    }

    return 0;
  } catch (e, stack) {
    logger.error('Failed to list admin accounts: $e', stack);
    return 1;
  }
}
