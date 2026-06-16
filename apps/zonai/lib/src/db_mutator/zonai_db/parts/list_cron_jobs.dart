part of zonai_db;

extension _ListCronJobsX on ZonaiDb {
  Future<List<String>> _listCronJobs({required Jwt jwt}) async {
    if (!jwt.admin.isAdmin) {
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
      return response.names;
    } finally {
      await mailman.kill(failPending: false);
    }
  }
}
