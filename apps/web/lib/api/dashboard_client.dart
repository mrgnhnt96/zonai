import 'dart:convert';

import 'package:revali_client/revali_client.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/gen/client/client.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

Future<DashboardMetrics> fetchDashboardMetrics({required Server server, int? since, bool excludeAdmin = false}) async {
  final token = ZonaiCookie.authToken.read();
  final headers = <String, String>{if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token'};

  final response = await server.client.request(
    method: 'GET',
    path: '/dashboard/metrics',
    query: {if (since != null) 'since': since, if (excludeAdmin) 'exclude_admin': true},
    headers: headers,
  );

  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ServerException(
      message: 'Dashboard metrics failed (${response.statusCode})',
      statusCode: response.statusCode,
      body: body,
    );
  }

  final decoded = jsonDecode(body);
  final data = decoded is Map ? decoded['data'] ?? decoded : null;
  if (data is! Map) {
    throw StateError('Dashboard metrics returned an unexpected response');
  }

  return DashboardMetrics.fromJson(Map<String, dynamic>.from(data));
}
