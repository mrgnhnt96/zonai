part of zonai_db;

extension _RunCronJobX on ZonaiDb {
  /// Whether [jwt] may run the cron called [name].
  ///
  /// An API token reaches `/crons` only through [ZonaiDb.parseCronJwt], and
  /// what it may run is exactly the crons its scope names -- its `admin` grant
  /// is about tables and plays no part. Everyone else must be an admin.
  bool _mayRunCron(Jwt jwt, String name) {
    return switch (jwt) {
      ApiTokenJwt(:final scope) => scope.allowsCron(name),
      _ => jwt.admin.isAdmin,
    };
  }

  /// Runs the cron called [name] once, now, and answers what it wrote.
  ///
  /// The job's writes reach this host with the worker's reply (see
  /// [Receivable.isOutOfBandNotification]) and are committed on the write
  /// chain before this returns -- including those of a job that failed part
  /// way, as a scheduled run's are -- so [CronRunResult.changes] is what is
  /// already in the database.
  Future<CronRunResult> _runCronJob({
    required Jwt jwt,
    required String name,
  }) async {
    if (!_mayRunCron(jwt, name)) {
      throw const TableAccessDeniedException(
        table: '_cron_jobs',
        operation: 'run',
      );
    }

    final stopwatch = Stopwatch()..start();
    final mailman = CronMailman();
    final CronJobRunResponse response;
    try {
      response = await mailman.send<CronJobRunResponse>(
        RunCronJobRequest(name: name),
      );
    } finally {
      await mailman.kill(failPending: false);
    }

    final changes = <String, Map<String, int>>{};
    final pending = mutations.extract;
    if (pending.isNotEmpty) {
      await _runWrite(() async {
        mutations.addAll(pending);
        await _executeEffects(
          onWritten: (table, action, rows) {
            if (rows == 0) return;
            final actions = changes[table] ??= {};
            actions[action] = (actions[action] ?? 0) + rows;
          },
        );
      });
    }
    stopwatch.stop();

    return CronRunResult(
      name: name,
      ok: response.accepted,
      ms: stopwatch.elapsedMilliseconds,
      changes: changes,
      error: switch (response) {
        CronJobRunResponse(accepted: true) => null,
        CronJobRunResponse(:final error) => error ?? 'Cron job failed',
      },
    );
  }
}
