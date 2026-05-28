import 'package:cron/cron.dart';

abstract base class CronJob {
  const CronJob({
    required this.name,
    required this.schedule,
    this.enabled = true,
    this.strict = true,
    this.runOnStartup = false,
  });

  final String name;
  final Schedule schedule;
  final bool enabled;

  /// Whether to run the cron only on the schedule, or
  /// on the next available time
  ///
  /// If true, the job will only run on the schedule.
  ///
  /// When false, the job will run if the schedule was potentially missed.
  /// This is useful if your server machine was offline or scaled down.\
  /// There must be a previous run to check against to determine if the job should be run.
  final bool strict;

  /// Whether to run the job on startup.
  final bool runOnStartup;

  Future<void> run();
}
