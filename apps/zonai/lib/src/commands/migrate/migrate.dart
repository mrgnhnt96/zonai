import '../../deps/args.dart';
import '../../deps/logger.dart';
import '../../deps/migrate.dart' as deps;

part '__generate.dart';

const _usage = '''
Usage: zonai db migrate [options] <subcommand>

Subcommands:
  generate            Generate SQL migrations from schema changes (implied
                      when --name is passed with no subcommand)
  apply               Apply pending SQL migrations to the database

Options:
  -h, --help          Show help information
  -n, --name=<name>   Name for the generated migration (generate only)
      --dry-run       Show what would be generated without writing files
                      (generate only)
  -c, --config=<path> Path to zonai.yml
''';

const _applyUsage = '''
Usage: zonai db migrate apply [options]

Apply every pending SQL migration in the migrations directory to the
database, in order.

Options:
  -h, --help          Show help information
  -c, --config=<path> Path to zonai.yml
''';

/// Routes `zonai db migrate` subcommands (e.g. [generate]) using [Settings]
/// paths.
Future<int> migrate(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  if (path.isEmpty && args.getOrNull<String>('name', abbr: 'n') != null) {
    return await _generate();
  }

  switch (path) {
    case ['generate' || 'g' || 'gen']:
      return await _generate();
    case ['apply' || 'up']:
      // `apply --help` used to apply the pending migrations and report
      // success -- on whatever database the current directory resolves to.
      if (args.help) {
        logger.info(_applyUsage);
        return 1;
      }
      return await deps.migrate.applyPending();
    default:
      logger.info(_usage);
      return 1;
  }
}
