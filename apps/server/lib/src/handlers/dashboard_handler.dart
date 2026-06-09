import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/payloads/dashboard_metrics.dart';

class DashboardHandler {
  const DashboardHandler();

  Future<DashboardMetrics> metrics(String? authorization, {int? since}) async {
    final jwt = await zonaiDB.parseJwt(
      _parseBearerAuthorization(authorization),
    );
    if (jwt == null || jwt.admin.isAdmin != true) {
      throw const TableAccessDeniedException(
        table: '_dashboard',
        operation: 'metrics',
      );
    }

    return zonaiDB.dashboardMetrics(jwt: jwt, since: since);
  }

  String? _parseBearerAuthorization(String? authorizationHeader) {
    if (authorizationHeader == null) {
      return null;
    }

    final trimmed = authorizationHeader.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      return trimmed.substring(prefix.length).trim();
    }

    return null;
  }
}
