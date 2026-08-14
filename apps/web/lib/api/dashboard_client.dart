import 'package:zonai_client/server.dart';
import 'package:zonai_schema/payloads.dart';

Future<DashboardMetrics> fetchDashboardMetrics({required Server server, int? since, bool excludeAdmin = false}) {
  return server.dashboard.metrics(since: since, excludeAdmin: excludeAdmin);
}
