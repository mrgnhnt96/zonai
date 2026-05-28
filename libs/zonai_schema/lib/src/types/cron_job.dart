import 'package:cron/cron.dart';

class CronJob {
  const CronJob({
    required this.name,
    required this.schedule,
    required this.callback,
    this.enabled = true,
    this.strict = true,
  });

  final String name;
  final Schedule schedule;
  final Future<void> Function() callback;
  final bool enabled;

  /// Whether to run the cron only on the schedule, or
  /// on the next available time
  final bool strict;
}
