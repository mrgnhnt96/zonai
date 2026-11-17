part of zonai_db;

extension _ListCronJobsX on ZonaiDb {
  /// The crons [jwt] may run: all of them for an admin, and for an API token
  /// only those its scope names.
  Future<List<String>> _listCronJobs({required Jwt jwt}) async {
    if (jwt is! ApiTokenJwt && !jwt.admin.isAdmin) {
      throw const TableAccessDeniedException(
        table: '_cron_jobs',
        operation: 'list',
      );
    }

    final mailman = CronMailman();
    try {
      final response = await mailman.send<ListCronJobsResponse>(
        ListCronJobsRequest(),
      );
      return [
        for (final name in response.names)
          if (_mayRunCron(jwt, name)) name,
      ];
    } finally {
      await mailman.kill(failPending: false);
    }
  }
}
