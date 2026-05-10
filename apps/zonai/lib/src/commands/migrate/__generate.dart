part of 'migrate.dart';

const _generateUsage = '''
Usage: zonai migrate generate [options]

Options:
  -h, --help      Show help information
  -n, --name      Name for the migration
  --dry-run       Show what would be generated without creating files
''';

Future<int> _generate() async {
  if (args.help) {
    print(_generateUsage);
    return 1;
  }

  final name = switch (args['name']) {
    final String name => name,
    _ => null,
  };

  if (name == null) {
    logger.error('Missing required argument: --name');
    return 1;
  }

  final exitCode = deps.migrate.run(
    name: name,
    dryRun: args.getOrNull('dry-run'),
  );
  return exitCode;
}
