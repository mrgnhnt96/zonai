import '../db_mutator/mailman.dart';
import '../deps/logger.dart';
import '../messengers/config_mailman.dart';
import '../messengers/cron_mailman.dart';
import '../messengers/extensions_mailman.dart';
import '../messengers/operations_mailman.dart';
import '../messengers/rate_limit_mailman.dart';
import '../messengers/rules_mailman.dart';

Future<int> ping() async {
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
