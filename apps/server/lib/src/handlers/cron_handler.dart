import 'package:zonai/deps.dart';

import 'package:zonai_schema/payloads.dart';

class CronHandler {
  const CronHandler();

  Future<CronJobList> list(String? authorization) async {
    final jwt = await zonaiDB.parseJwt(
      _parseBearerAuthorization(authorization),
    );
    if (jwt == null || jwt.admin.isAdmin != true) {
      throw const TableAccessDeniedException(
        table: '_cron_jobs',
        operation: 'list',
      );
    }

    final names = await zonaiDB.listCronJobs(jwt: jwt);
    return CronJobList(names: names);
  }

  Future<void> run(String? authorization, {required String name}) async {
    final jwt = await zonaiDB.parseJwt(
      _parseBearerAuthorization(authorization),
    );
    if (jwt == null || jwt.admin.isAdmin != true) {
      throw const TableAccessDeniedException(
        table: '_cron_jobs',
        operation: 'run',
      );
    }

    await zonaiDB.runCronJob(jwt: jwt, name: name);
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
