import '../../deps/args.dart';
import '../../deps/logger.dart';
import 'admin/add.dart';
import 'admin/list.dart';
import 'admin/remove.dart';
import 'admin/reset_password.dart';

const _usage = '''
Usage: zonai db admin [options] <subcommand>

Options:
  -h, --help          Show help information

Subcommands:
  add                 Create a new admin account
  list                List every admin account
  reset-password      Reset an existing admin account's password
  remove              Remove an existing admin account
''';

Future<int> admin(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['add' || 'create' || 'new']:
      return await addAdmin();
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
