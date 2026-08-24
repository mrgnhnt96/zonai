// `PasswordResetReason` is not on zonai_schema's public barrel -- the table
// it belongs to is internal. Imported from src the same way
// `apps/zonai/lib/src/exceptions/auth_exception.dart` and `zonai_db.dart`
// already do.
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart'
    show PasswordResetReason;

import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _usage = '''
Usage: zonai db admin require-password-reset [options]

Require an admin account to choose a new password before it may sign in
again, and revoke every session it currently holds.

The account keeps its current password: the password still verifies, but a
password sign-in answers 403 with a one-time reset ticket instead of a
session, until a new password is set. Sign-in by OTP, magic link or OAuth is
untouched -- the requirement is a statement about the password credential,
and someone who proved possession of their mailbox has not used it.

This needs no secret and no running server, which is what makes it the
recovery path when a password has leaked and nobody can reach the dashboard.

Options:
  -h, --help              Show help information
  -e, --email=<address>   Admin email address (required)
      --clear             Lift the requirement instead of setting one. The
                           escape hatch for one set on the wrong address --
                           without it a typo locks someone out of an account
                           they still own. Sessions already revoked stay
                           revoked.
      --reason=<name>     Why the account owes a password, carried to the
                           client in the 403 so it can say something truer
                           than "you must reset". One of:
                             admin-forced       (default) an operator said so
                             compromised        the password is believed known
                                                 to someone else
                             temporary-password somebody other than the owner
                                                 chose the current one
                             password-policy    a rotation/age policy
''';

/// `admin-forced`, not `adminForced`: every other CLI value in this tool is
/// kebab-case, and an operator typing an enum's Dart identifier is a leak of
/// how this is implemented. Both spellings are accepted so neither guess is
/// wrong at 3am.
const _reasons = <String, PasswordResetReason>{
  'admin-forced': PasswordResetReason.adminForced,
  'adminforced': PasswordResetReason.adminForced,
  'compromised': PasswordResetReason.compromised,
  'temporary-password': PasswordResetReason.temporaryPassword,
  'temporarypassword': PasswordResetReason.temporaryPassword,
  'password-policy': PasswordResetReason.passwordPolicy,
  'passwordpolicy': PasswordResetReason.passwordPolicy,
};

Future<int> requireAdminPasswordReset() async {
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

  final clear = args.getOrNull<bool>('clear') == true;

  // Read before the branch so `--clear --reason=compromised` is refused
  // rather than silently ignored: an operator who spelled out a reason and
  // got "Cleared" reasonably believes something else happened.
  final rawReason = args.getOrNull<String>('reason');
  if (clear && rawReason != null) {
    logger.error('--reason has no meaning with --clear');
    logger.info(_usage);
    return 1;
  }

  final reason = switch (rawReason) {
    null => PasswordResetReason.adminForced,
    final raw => _reasons[raw.toLowerCase()],
  };
  if (reason == null) {
    logger.error(
      'Unknown --reason "$rawReason". Expected one of: '
      'admin-forced, compromised, temporary-password, password-policy',
    );
    logger.info(_usage);
    return 1;
  }

  try {
    final table = await zonaiDB.adminPasswordTable();

    if (clear) {
      final removed = await zonaiDB.clearPasswordResetRequirement(
        table: table,
        email: email,
      );

      // "Nothing to clear" is not a failure -- an operator clearing a
      // requirement that has already been satisfied gets the state they
      // asked for. It is reported as a distinct sentence rather than as the
      // same "Cleared" so a typo'd address does not read as a success.
      if (removed) {
        logger.info('Cleared the password reset requirement for $email');
      } else {
        logger.info('$email had no password reset requirement to clear');
      }

      return 0;
    }

    await zonaiDB.requirePasswordReset(
      table: table,
      email: email,
      reason: reason,
      byUserId: 'cli',
    );

    logger.info('$email must set a new password before signing in');
    logger.info('  reason: ${reason.name}');
    logger.info('  every session it held has been revoked');

    return 0;
  } catch (e, stack) {
    logger.error('Failed to require a password reset: $e', stack);
    return 1;
  }
}
