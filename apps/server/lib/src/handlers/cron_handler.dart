import 'package:zonai/deps.dart';

import 'package:zonai_schema/payloads.dart';
import 'package:zonai_server/src/exceptions/cron_run_failed_exception.dart';

/// `/crons`: an admin session, or an API token whose scope names crons.
///
/// Which crons the caller may run or see is decided in the db mutator; this
/// only refuses a request that carries no credential at all.
class CronHandler {
  const CronHandler();

  Future<CronJobList> list(String? authorization) async {
    final jwt = await zonaiDB.parseCronJwt(
      _parseBearerAuthorization(authorization),
    );
    if (jwt == null) {
      throw const TableAccessDeniedException(
        table: '_cron_jobs',
        operation: 'list',
      );
    }

    final names = await zonaiDB.listCronJobs(jwt: jwt);
    return CronJobList(names: names);
  }

  /// Answers what the run wrote, or throws [CronRunFailedException] carrying
  /// the same when the job failed.
  Future<CronRunResult> run(
    String? authorization, {
    required String name,
  }) async {
    final jwt = await zonaiDB.parseCronJwt(
      _parseBearerAuthorization(authorization),
    );
    if (jwt == null) {
      throw const TableAccessDeniedException(
        table: '_cron_jobs',
        operation: 'run',
      );
    }

    final result = await zonaiDB.runCronJob(jwt: jwt, name: name);
    if (!result.ok) throw CronRunFailedException(result);
    return result;
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
