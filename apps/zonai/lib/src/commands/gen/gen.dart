import '../../deps/args.dart';
import '../../deps/logger.dart';
import 'client.dart';

const _usage = '''
Usage: zonai gen <subcommand> [options]

Subcommands:
  client          Generate a typed Dart client from the project's schema

Options:
  -h, --help      Show help information

Run `zonai gen <subcommand> --help` for a subcommand's own options.
''';

Future<int> gen(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['client']:
      return await client();

    default:
      logger.info(_usage);
      return 1;
  }
}
