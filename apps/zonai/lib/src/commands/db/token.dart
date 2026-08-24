import '../../deps/args.dart';
import '../../deps/logger.dart';
import 'token/create.dart';
import 'token/list.dart';
import 'token/revoke.dart';

const _usage = '''
Usage: zonai db token [options] <subcommand>

Options:
  -h, --help          Show help information

Subcommands:
  create              Mint a token and print it once
  list                List every token, with what each may reach
  revoke              Stop a token working, keeping the record
  delete              Remove a token's row entirely

An API token is a credential for the data API that needs no sign-in, no
mailbox and no password, and can be issued without an expiry. It is how a
backup script, a CI job or a partner integration talks to the database.

These commands write to the database file directly -- no running server, no
session, and no JWT signing secret. Filesystem access to the database IS the
authorization, which is the same assumption `zonai db admin add` makes.
''';

Future<int> token(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['create' || 'new' || 'add' || 'mint']:
      return await createToken();
    case ['list' || 'ls']:
      return await listTokens();
    // The id is a positional, so it arrives here as the rest of the path --
    // `Args.parse` only fills `rest` once a flag has been seen.
    case ['revoke', ...final rest]:
      return await revokeToken(rest.firstOrNull);
    case ['delete' || 'rm' || 'remove' || 'forget', ...final rest]:
      return await deleteToken(rest.firstOrNull);
    default:
      logger.info(_usage);
      return 1;
  }
}
