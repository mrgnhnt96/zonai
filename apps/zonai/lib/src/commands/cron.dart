import '../deps/args.dart';
import '../deps/logger.dart';
import '../messengers/cron_mailman.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';

const _usage = '''
Usage: zonai cron run <job-name>

Manually run a cron job by name.

Options:
  -h, --help      Show help information
''';

Future<int> cron(List<String> path) async {
  if (args.help && path.isEmpty) {
    logger.info(_usage);
    return 1;
  }

  switch (path) {
    case ['run', final String name] when name.isNotEmpty:
      return await _runJob(name);
    default:
      logger.info(_usage);
      return 1;
  }
}

Future<int> _runJob(String name) async {
  final mailman = CronMailman();
  try {
    logger.info('Running cron job: $name');
    await mailman.send(RunCronJobRequest(name: name));
    logger.info('Cron job finished: $name');
    return 0;
  } catch (e, stack) {
    logger.error('Cron job failed: $e', e, stack);
    return 1;
  } finally {
    await mailman.kill(failPending: false);
  }
}
