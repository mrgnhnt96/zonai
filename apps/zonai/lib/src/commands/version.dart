import 'package:zonai/gen/version.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/versions.dart';

const _usage = '''
Usage: zonai version [subcommand]

With no subcommand, prints the installed version and whether ops/rules
dispatch in-process or over worker IPC.

Subcommands:
  update          Download and install the latest version
  check           Report whether a newer version is available

Options:
  -h, --help      Show help information
''';

Future<int> version(List<String> path) async {
  if (args.help) {
    logger.info(_usage);
    return 0;
  }

  if (path.isEmpty) {
    logger.info('Zonai: v$kVersion');
    // The only way to ask a binary which dispatch it actually got.
    //
    // Both answers work, which is the problem: a build that silently lost
    // in-process ops/rules serves exactly like one that kept them, so nothing
    // in the bundle -- or in a deploy's logs -- distinguished them. That is
    // what let `zonai build` ship the wrong one for two releases (see
    // docs/build-fallback-next-steps.md). This is the line
    // tool/ci/verify_build_command.sh asserts on, and the one to ask a
    // machine after the fact.
    //
    // Reported from `useInProcessOperations` rather than from whether the
    // registries are set, so ZONAI_FORCE_WORKERS shows up here too: what is
    // claimed is what dispatch will do, not what was compiled in.
    final dispatch = HostWorkerRegistries.useInProcessOperations
        ? 'in-process (project-linked)'
        : 'worker IPC';
    logger.info('Ops/rules: $dispatch');
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
