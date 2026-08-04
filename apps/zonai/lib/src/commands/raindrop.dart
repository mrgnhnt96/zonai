import 'package:zonai/deps.dart';
import 'package:zonai/gen/internal/raindrop/raindrop_bundle.dart';
import 'package:zonai/src/domain/constants.dart';

const _usage = '''
Usage: zonai raindrop [options]

Options:
  sync            Force re-sync the embedded raindrop bundle into this project
  info            Show the current raindrop bundle version and sync status

  -h, --help      Show help information
''';

Future<int> raindrop(List<String> path) async {
  if (args.help) {
    logger.info(_usage);
    return 0;
  }

  switch (path) {
    case ['sync']:
      return await _sync();
    case ['info']:
      return _info();
    default:
      logger.info(_usage);
      return 1;
  }
}

Future<int> _sync() async {
  if (!kIsCompiled) {
    logger.info(
      'Not available in dev/source runs -- this monorepo uses raindrop '
      'directly via the submodule.',
    );
    return 0;
  }

  await raindropSync.ensure(force: true);
  logger.info(
    'Raindrop bundle synced (${kRaindropBundleHash.substring(0, 12)}).',
  );
  return 0;
}

int _info() {
  if (!kIsCompiled) {
    logger.info(
      'Not available in dev/source runs -- this monorepo uses raindrop '
      'directly via the submodule.',
    );
    return 0;
  }

  logger.info('Embedded bundle hash: ${kRaindropBundleHash.substring(0, 12)}');

  final stamp = raindropSync.readStamp();
  if (stamp == null) {
    logger.info('Project sync status: never synced.');
    return 0;
  }

  logger.info('Project stamp hash:   ${stamp.hash.substring(0, 12)}');
  logger.info(
    'Project sync status:  ${raindropSync.isUpToDate ? 'up to date' : 'stale'}',
  );
  for (final entry in stamp.overrides.entries) {
    logger.info('  ${entry.key} -> ${entry.value}');
  }

  return 0;
}
