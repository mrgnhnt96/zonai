part of zonai_db;

extension _RunCronJobX on ZonaiDb {
  Future<void> _runCronJob({required Jwt jwt, required String name}) async {
    if (!jwt.admin.isAdmin) {
      throw const TableAccessDeniedException(
        table: '_cron_jobs',
        operation: 'run',
      );
    }

    final mailman = CronMailman();
    try {
      final response = await mailman.send<CronJobRunResponse>(
        RunCronJobRequest(name: name),
      );

      if (!response.accepted) {
        throw StateError(response.error ?? 'Cron job was not accepted');
      }
    } finally {
      await mailman.kill(failPending: false);
    }
  }
}
