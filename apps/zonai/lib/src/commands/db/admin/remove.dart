import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db admin remove [options]

Remove an existing admin account. This makes `add` recoverable: an email
freed this way can be re-added later.

Options:
  -h, --help          Show help information
  -e, --email         Admin email address (required)
''';

Future<int> removeAdmin() async {
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final email = args.getOrNull<String>('email', abbr: 'e');
  if (email == null || email.isEmpty) {
    logger.error('Missing required option: --email');
    logger.info(_usage);
    return 1;
  }

  try {
    await zonaiDB.removeAdmin(email: email);

    logger.info('Removed admin account: $email');

    return 0;
  } catch (e, stack) {
    logger.error('Failed to remove admin account: $e', stack);
    return 1;
  }
}
