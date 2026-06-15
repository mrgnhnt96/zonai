import 'dart:async';

import 'package:cron/cron.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/types/cron_job.dart';
import 'package:zonai_schema/src/utils/cron_extension.dart';

class DbCrons {
  DbCrons({required this.jobs, Cron? cron}) : cron = cron ?? Cron() {
    handler = MessageHandler(
      fromUnknownRequest: CronRequest.fromRequest,
      onMessage: (request) async {
        switch (request) {
          case RunCronJobRequest():
            return await _manuallyRunJob(request);
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
          case CleanupUnreferencedPhotosRequest():
            throw Exception(
              '$CleanupUnreferencedPhotosRequest should not be called from main thread',
            );
        }
      },
    );
  }

  final Cron cron;
  final List<CronJob> jobs;
  late final MessageHandler<CronRequest> handler;

  List<ScheduledTask> tasks = [];

  void start() {
    handler.listen();
  }

  Future<CronJobRunResponse> _manuallyRunJob(RunCronJobRequest request) async {
    for (final job in jobs) {
      if (job.name == request.name) {
        // Run on a separate request so job lifecycle notifications (which reuse
        // the run request id) cannot complete the host's pending CronJobRunResponse.
        _runJob(job, RunCronJobRequest(name: job.name)).ignore();
        return CronJobRunResponse(
          id: request.id,
          name: job.name,
          accepted: true,
        );
      }
    }

    return CronJobRunResponse(
      id: request.id,
      name: request.name,
      accepted: false,
      error: 'Job not found: ${request.name}',
    );
  }

  Future<({bool succeeded, String? error})> _runJob(
    CronJob job, [
    RunCronJobRequest? r,
  ]) async {
    final request = r ?? RunCronJobRequest(name: job.name);

    try {
      msg.notify(JobStarted(id: request.id, name: job.name));
      await handler.runWithParent(request, job.run);
      msg.notify(JobCompleted(id: request.id, name: job.name));
      return (succeeded: true, error: null);
    } catch (e, stack) {
      msg.notify(
        JobFailed(
          id: request.id,
          name: job.name,
          error: e.toString(),
          stackTrace: stack.toString(),
        ),
      );
      return (succeeded: false, error: e.toString());
    }
  }

  Future<void> _startCrons() async {
    for (final job in jobs) {
      final task = cron.schedule(job.schedule, () => _runJob(job));

      if (job.runOnStartup) {
        await _runJob(job);

        // if the job is not strict, then we can potentially run the job
        // right away. There must always be a previous run to check against
      } else if (!job.strict) {
        final lastRun = await msg.request<LastJobRunResponse>(
          LastJobRunRequest(name: job.name),
        );

        if (lastRun.time case final time?) {
          if (job.schedule.isDue(time)) {
            await _runJob(job);
          }
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
