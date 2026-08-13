import '../db_mutator/mailman.dart';
import '../deps/args.dart';
import '../deps/logger.dart';
import '../messengers/config_mailman.dart';
import '../messengers/cron_mailman.dart';
import '../messengers/extensions_mailman.dart';
import '../messengers/operations_mailman.dart';
import '../messengers/rate_limit_mailman.dart';
import '../messengers/rules_mailman.dart';

const _usage = '''
Usage: zonai ping [options]

Spawn each compiled worker in .zonai/executables/ and report whether it
answers, then shut it back down. The server does not need to be running.

Options:
  -h, --help            Show help information
  -c, --config=<path>   Path to zonai.yml
''';

Future<int> ping() async {
  // Spawning six worker subprocesses is not what `--help` asked for.
  if (args.help) {
    logger.info(_usage);
    return 1;
  }

  final mailmen = <(Mailman<dynamic, dynamic>, String)>[
    (ExtensionsMailman(), 'extension'),
    (RulesMailman(), 'rules'),
    (OperationsMailman(), 'operation'),
    (ConfigMailman(), 'config'),
    (CronMailman(), 'cron'),
    (RateLimitsMailman(), 'rate limit'),
  ];

  for (final (mailman, name) in mailmen) {
    final success = await mailman.ping();
    logger.info('Ping $name ${success ? 'succeeded' : 'failed'}');
    await mailman.kill(failPending: false);
  }

  return 0;
}
