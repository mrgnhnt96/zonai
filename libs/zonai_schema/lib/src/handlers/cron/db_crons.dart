import 'package:cron/cron.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/cron_job.dart';
import 'package:zonai_schema/src/utils/cron_extension.dart';

class DbCrons {
  DbCrons({required this.jobs, Cron? cron}) : cron = cron ?? Cron();

  final Cron cron;
  final List<CronJob> jobs;

  List<ScheduledTask> tasks = [];

  void start() {
    MessageHandler(
      onMessage: (UnknownRequest msg) async {
        final request = CronRequest.fromRequest(msg);

        switch (request) {
          case StartCronsRequest():
            _startCrons();
            return CronsStarted(id: request.id);
          case StopCronsRequest():
            await _stopCrons();
            return CronsStopped(id: request.id);
          case LastJobRunRequest():
            throw Exception(
              '$LastJobRunRequest should not be called from main thread',
            );
        }
      },
    ).listen();
  }

  Future<void> _runJob(CronJob job) async {
    try {
      msg.notify(JobStarted(name: job.name));
      await job.callback();
      msg.notify(JobCompleted(name: job.name));
    } catch (e, stack) {
      msg.notify(
        JobFailed(
          name: job.name,
          error: e.toString(),
          stackTrace: stack.toString(),
        ),
      );
    }
  }

  Future<void> _startCrons() async {
    for (final job in jobs) {
      final task = cron.schedule(job.schedule, () => _runJob(job));

      final lastRun = await msg.request<LastJobRunResponse>(
        LastJobRunRequest(name: job.name),
      );

      if (lastRun.time case final time?) {
        if (job.schedule.isDue(time)) {
          await _runJob(job);
        }
      }

      tasks.add(task);
    }
  }

  Future<void> _stopCrons() async {
    for (final task in tasks) {
      await task.cancel();
    }
    tasks.clear();
  }
}
