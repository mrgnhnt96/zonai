import 'package:zonai_cli/src/commands/migrate.dart';
import 'package:zonai_cli/src/commands/serve.dart';
import 'package:zonai_cli/src/deps/args.dart';

const _usage = '''
Usage: zonai <command>

Commands:
  help        Show help information
  version     Show version information
  migrate     Migrate the database
  serve       Serve the application
''';

Future<void> run() async {
  if (args['help'] case null || true) {
    print(_usage);
    return;
  }

  if (args.path.isEmpty) {
    print(_usage);
    return;
  }

  switch (args.path) {
    case ['migrate']:
      migrate();
    case ['serve']:
      serve();
  }
}
