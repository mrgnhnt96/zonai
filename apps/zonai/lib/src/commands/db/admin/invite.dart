import '../../../deps/args.dart';
import '../../../deps/logger.dart';
import '../../../deps/zonai_db.dart';

const _inviteUsage = '''
Usage: zonai db admin invite [options]

Email an invite to become an admin. Unlike `admin add`, this creates no
account: the row exists only once the invitee opens the link and proves
they own the address. Reach for this whenever the address belongs to
someone other than you.

The invite is good for 7 days and can be cancelled with
`zonai db admin revoke-invite` at any point before it is accepted.

Requires the app's email sending to be configured -- the link only exists
in the email.

Options:
  -h, --help              Show help information
  -e, --email=<address>   Address to invite (required)
''';

const _listUsage = '''
Usage: zonai db admin invites [options]

List admin invites that are still outstanding -- neither accepted, revoked
nor expired. Never prints the invite token; it exists only in the email.

Options:
  -h, --help              Show help information
''';

const _revokeUsage = '''
Usage: zonai db admin revoke-invite [options]

Cancel an outstanding admin invite. The link stops working immediately.

Succeeds whether or not an invite was actually pending, so a typo here
does not become a second thing to diagnose.

Options:
  -h, --help              Show help information
  -e, --email=<address>   Address whose invite to cancel (required)
''';

Future<int> inviteAdmin() async {
  if (args.help) {
    logger.info(_inviteUsage);
    return 1;
  }

  final email = args.getOrNull<String>('email', abbr: 'e');
  if (email == null || email.isEmpty) {
    logger.error('Missing required option: --email');
    logger.info(_inviteUsage);
    return 1;
  }

  try {
    final invite = await zonaiDB.inviteAdminFromCli(email: email);

    logger.info(
      invite['isResend'] == true ? 'Admin invite resent' : 'Admin invite sent',
    );
    logger.info('  email: ${invite['email']}');
    logger.info('  table: ${invite['table']}');
    logger.info('  expires: ${invite['expiresAt']}');
    logger.info('');
    logger.info(
      'No admin account exists yet. It is created when they open the link '
      'and sign in.',
    );

    return 0;
  } catch (e, stack) {
    logger.error('Failed to invite admin: $e', stack);
    return 1;
  }
}

Future<int> listAdminInvites() async {
  if (args.help) {
    logger.info(_listUsage);
    return 1;
  }

  try {
    final invites = await zonaiDB.listAdminInvitesFromCli();

    if (invites.isEmpty) {
      logger.info('No pending admin invites');
      return 0;
    }

    logger.info('${invites.length} pending admin invite(s):');
    for (final invite in invites) {
      logger.info('');
      logger.info('  email: ${invite['email']}');
      logger.info('  invited: ${invite['invitedAt']}');
      logger.info('  expires: ${invite['expiresAt']}');
      // Absent for invites issued from this CLI, which has no user to
      // attribute them to -- printing "null" would suggest a lost record
      // rather than one that was never there.
      if (invite['invitedByEmail'] case final invitedBy?) {
        logger.info('  invited by: $invitedBy');
      }
    }

    return 0;
  } catch (e, stack) {
    logger.error('Failed to list admin invites: $e', stack);
    return 1;
  }
}

Future<int> revokeAdminInvite() async {
  if (args.help) {
    logger.info(_revokeUsage);
    return 1;
  }

  final email = args.getOrNull<String>('email', abbr: 'e');
  if (email == null || email.isEmpty) {
    logger.error('Missing required option: --email');
    logger.info(_revokeUsage);
    return 1;
  }

  try {
    await zonaiDB.revokeAdminInviteFromCli(email: email);

    logger.info('Admin invite revoked for $email');
    logger.info('Any link already sent to that address no longer works.');

    return 0;
  } catch (e, stack) {
    logger.error('Failed to revoke admin invite: $e', stack);
    return 1;
  }
}
