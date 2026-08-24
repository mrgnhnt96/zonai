// `PasswordResetReason` is not on zonai_schema's public barrel -- the table it
// belongs to is internal. Imported from src the same way `zonai_db.dart` does.
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart'
    show PasswordResetReason;

import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db admin reset-password [options]

Reset an existing admin account's password. Use this to recover a
deployment where an admin account exists but nobody has the password.

Every session the account currently holds is revoked, always -- a reset is
the remedy for a password someone else may know, so the sessions that
password minted must not outlive it.

The new password is also TEMPORARY by default: the account must choose its
own before it may sign in again. Whoever ran this command knows the password
they just set, so a password that stays good is a credential shared between
two people for as long as nobody gets round to changing it.

Options:
  -h, --help              Show help information
  -e, --email=<address>   Admin email address (required)
  -p, --password=<value>  New admin password (required)
      --no-force-reset    Leave the new password standing -- do not require
                           the account to choose another. For an operator
                           resetting their OWN password, where there is no
                           second person to lock out.
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

  // `--no-force-reset` parses to `force-reset: false`, NOT to a
  // `no-force-reset` key -- Args.parse strips the `no-` prefix and stores the
  // negation under the bare name (utils/args.dart, the `--no-` branch). So the
  // key read here is the bare one and absence means "on". Reading
  // `'no-force-reset'` would be null on every real invocation and the flag
  // would do nothing; see the same mistake fixed in `add.dart`.
  final forceReset = args.getOrNull<bool>('force-reset') != false;

  try {
    await zonaiDB.resetAdminPassword(email: email, newPassword: password);

    logger.info('Password reset for $email');
    // Unconditional, because the revocation is: `resetAdminPassword` revokes
    // in the method now, so reporting it only under `--force-reset` would
    // leave a `--no-force-reset` operator unaware that the sessions they held
    // -- possibly their own -- are gone.
    logger.info('  every session it held has been revoked');

    if (forceReset) {
      // AFTER the password lands, never before. Requiring a reset against a
      // password change that then failed would lock the account out of a
      // credential that still works, using the command meant to restore
      // access. The reverse order fails safe: a requirement that does not get
      // set leaves the operator's new password usable, which is the
      // pre-feature behaviour rather than a lockout.
      final table = await zonaiDB.adminPasswordTable();
      await zonaiDB.requirePasswordReset(
        table: table,
        email: email,
        reason: PasswordResetReason.temporaryPassword,
        byUserId: 'cli',
      );

      logger.info('  this password is temporary: $email must choose its own');
      logger.info('  pass --no-force-reset to skip that');
    }

    return 0;
  } catch (e, stack) {
    logger.error('Failed to reset admin password: $e', stack);
    return 1;
  }
}
