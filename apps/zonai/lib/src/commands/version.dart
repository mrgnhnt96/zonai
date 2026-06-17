import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/versions.dart';

const _usage = '''
Usage: zonai version [options]

Options:
  update          Update to the latest version
  check           Check for updates

  -h, --help      Show help information
''';

Future<int> version(List<String> path) async {
  if (args.help) {
    logger.info(_usage);
    return 0;
  }

  if (path.isEmpty) {
    logger.info('Zonai: v$kVersion');
    return 0;
  }

  switch (path) {
    case ['update']:
      await versions.downloadUpdate();
      return 0;
    case ['check']:
      await versions.printVersionCheck();
      return 0;
    default:
      logger.info(_usage);
      return 1;
  }
}
