part of 'migrate.dart';

const _generateUsage = '''
Usage: zonai db migrate generate [options]

Diff the schemas against the database and write a new SQL migration.

Options:
  -h, --help          Show help information
  -n, --name=<name>   Name for the migration (required)
      --dry-run       Show what would be generated without writing files
  -c, --config=<path> Path to zonai.yml
''';

Future<int> _generate() async {
  if (args.help) {
    logger.info(_generateUsage);
    return 1;
  }

  // Read with the abbreviation declared: `-n` is parsed into `abbrs`, never
  // into `values`, so the documented short form used to fail as "missing".
  final name = args.getOrNull<String>('name', abbr: 'n');

  if (name == null) {
    logger.error('Missing required argument: --name');
    return 1;
  }

  final exitCode = deps.migrate.run(
    name: name,
    dryRun: args.getOrNull<bool>('dry-run'),
  );
  return exitCode;
}
