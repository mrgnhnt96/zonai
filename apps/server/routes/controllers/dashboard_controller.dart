import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/dashboard_handler.dart';
import 'package:zonai_schema/src/payloads/dashboard_metrics.dart';

@Controller('dashboard')
class DashboardController {
  const DashboardController({required this.dashboardHandler});

  final DashboardHandler dashboardHandler;

  @Get('metrics')
  Future<DashboardMetrics> metrics({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query('since') int? since,
    @Query('exclude_admin') bool? excludeAdmin,
  }) {
    return dashboardHandler.metrics(authorization, since: since, excludeAdmin: excludeAdmin);
  }
}
