import 'package:zonai_schema/payloads.dart';

/// A `POST /crons/run` whose job threw, or named no job.
///
/// Carries the whole [result] so the error answer still says what the run
/// wrote before it failed.
final class CronRunFailedException implements Exception {
  const CronRunFailedException(this.result);

  final CronRunResult result;

  /// No job by that name: the caller's mistake, not the job's.
  bool get isUnknownJob => result.error?.startsWith('Job not found') ?? false;

  @override
  String toString() => 'Cron "${result.name}" failed: ${result.error}';
}
