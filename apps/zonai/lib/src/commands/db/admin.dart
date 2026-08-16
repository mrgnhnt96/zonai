import '../../deps/args.dart';
import '../../deps/logger.dart';
import 'admin/add.dart';
import 'admin/invite.dart';
import 'admin/list.dart';
import 'admin/remove.dart';
import 'admin/reset_password.dart';

const _usage = '''
Usage: zonai db admin [options] <subcommand>

Options:
  -h, --help          Show help information

Subcommands:
  add                 Create a new admin account outright
  invite              Email an invite; the account is created on acceptance
  invites             List invites that are still outstanding
  revoke-invite       Cancel an outstanding invite
  list                List every admin account
  reset-password      Reset an existing admin account's password
  remove              Remove an existing admin account

`add` creates the account itself and is how the first admin exists at all.
`invite` creates nothing until the invitee proves they own the address --
the one to use when inviting someone else.
''';

Future<int> admin(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['add' || 'create' || 'new']:
      return await addAdmin();
    case ['invite']:
      return await inviteAdmin();
    case ['invites' || 'list-invites']:
      return await listAdminInvites();
    case ['revoke-invite' || 'revoke_invite' || 'uninvite']:
      return await revokeAdminInvite();
    case ['list' || 'ls']:
      return await listAdmins();
    case ['reset-password' || 'reset_password' || 'reset']:
      return await resetAdminPassword();
    case ['remove' || 'rm' || 'delete']:
      return await removeAdmin();
    default:
      logger.info(_usage);
      return 1;
  }
}
