import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db admin reset-password [options]

Reset an existing admin account's password. Use this to recover a
deployment where an admin account exists but nobody has the password.

Options:
  -h, --help          Show help information
  -e, --email         Admin email address (required)
  -p, --password      New admin password (required)
''';

Future<int> resetAdminPassword() async {
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

  final password = args.getOrNull<String>('password', abbr: 'p');
  if (password == null || password.isEmpty) {
    logger.error('Missing required option: --password');
    logger.info(_usage);
    return 1;
  }

  try {
    await zonaiDB.resetAdminPassword(email: email, newPassword: password);

    logger.info('Password reset for $email');

    return 0;
  } catch (e, stack) {
    logger.error('Failed to reset admin password: $e', stack);
    return 1;
  }
}
