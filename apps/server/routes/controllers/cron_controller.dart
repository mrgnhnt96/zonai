import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/cron_handler.dart';

@Controller('crons')
class CronController {
  const CronController({required this.cronHandler});

  final CronHandler cronHandler;

  @Post('run')
  Future<void> run({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query('name') required String name,
  }) {
    return cronHandler.run(authorization, name: name);
  }
}
