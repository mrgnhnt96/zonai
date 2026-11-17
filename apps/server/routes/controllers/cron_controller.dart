import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/cron_handler.dart';
import 'package:zonai_schema/payloads.dart';

@Controller('crons')
class CronController {
  const CronController({required this.cronHandler});

  final CronHandler cronHandler;

  @Get('list')
  Future<CronJobList> list({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
  }) {
    return cronHandler.list(authorization);
  }

  /// Runs one cron now. Answers `CronRunResult`: which rows it wrote, by
  /// table and action. A failed run answers the same shape with `ok` false
  /// and its `error`, as a 500 (404 when there is no such cron).
  @Post('run')
  Future<CronRunResult> run({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query('name') required String name,
  }) {
    return cronHandler.run(authorization, name: name);
  }
}
