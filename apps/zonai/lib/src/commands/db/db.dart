import 'package:zonai/src/domain/constants.dart';

import 'admin.dart';
import 'clear.dart';
import 'email.dart';
import 'logs.dart';
import 'photos.dart';
import 'test.dart';
import 'token.dart';
import '../migrate/migrate.dart';
import '../../deps/args.dart';
import '../../deps/logger.dart';

const _usage = '''
Usage: zonai db <subcommand> [options]

Subcommands:
  migrate         Manage SQL migrations
  admin           Manage admin accounts
  token           Manage API tokens for the data API
  logs            Manage internal log records
  email           Send test emails
  clear           Delete the local database file

Options:
  -h, --help      Show help information

Run `zonai db <subcommand> --help` for a subcommand's own options.
''';

Future<int> db(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['migrate' || 'migrations' || 'm' || 'migration', ...final path]:
      return await migrate(path);

    case ['test'] when !kIsCompiled:
      return await test();

    case ['photos' || 'photo'] when !kIsCompiled:
      return await photos();

    case ['admin', ...final path]:
      return await admin(path);

    case ['token' || 'tokens' || 'api-token' || 'api-tokens', ...final path]:
      return await token(path);

    case ['logs' || 'log', ...final path]:
      return await logs(path);

    case ['email', ...final path]:
      return await email(path);

    case ['clear' || 'reset']:
      return await clearDatabase();

    default:
      logger.info(_usage);
      return 1;
  }
}
