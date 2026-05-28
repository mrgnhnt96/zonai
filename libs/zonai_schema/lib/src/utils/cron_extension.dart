import 'package:cron/cron.dart';

extension ScheduleX on Schedule {
  /// Whether a scheduled run was missed since [lastRun] and should run now.
  bool isDue(DateTime lastRun, {DateTime? at}) {
    at ??= .now();
    if (!at.isAfter(lastRun)) return false;

    var cursor = _tickAfter(lastRun);
    while (!cursor.isAfter(at)) {
      if (shouldRunAt(cursor)) return true;
      cursor = _tickAfter(cursor);
    }
    return false;
  }

  bool get _ticksBySecond =>
      seconds != null &&
      seconds!.isNotEmpty &&
      (seconds!.length != 1 || !seconds!.contains(0));

  DateTime _tickAfter(DateTime time) {
    if (_ticksBySecond) {
      return time.add(const Duration(seconds: 1));
    }
    return DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute,
    ).add(const Duration(minutes: 1));
  }
}
