import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/src/payloads/push_test_send.dart';
import 'package:zonai_server/src/handlers/push_handler.dart';

/// The dashboard's test-send route.
///
/// `POST`, not `GET`. Sending a notification to a real device is not safe or
/// idempotent in the HTTP sense, and a `GET` that pushes to a phone is one
/// prefetch away from doing it unasked — the same reasoning that puts every
/// maintenance verb on `POST`.
@Controller('dashboard/push')
class PushController {
  const PushController({required this.pushHandler});

  final PushHandler pushHandler;

  @Post('test')
  Future<PushTestSendResult> sendTest({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required PushTestSendBody body,
  }) {
    return pushHandler.sendTest(authorization, body: body);
  }
}
