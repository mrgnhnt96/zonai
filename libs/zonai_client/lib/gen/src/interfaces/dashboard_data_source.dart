part of '../../interfaces.dart';

abstract interface class DashboardDataSource {
  const DashboardDataSource();

  Future<DashboardMetrics> metrics({
    int? since,
    bool? excludeAdmin,
    String? authorization,
  });
  Future<StorageMetrics> storage({String? authorization});
}
