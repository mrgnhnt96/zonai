import 'package:revali_client/revali_client.dart';
import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/webhook_handler.dart';

import '../components/black_list.dart';
import '../components/webhook_rate_limit.dart';

/// Third-party callbacks (Resend, Stripe, ...) into the app's webhooks.
///
/// Unauthenticated by design: the sender cannot hold a zonai token. The app's
/// webhook gets the body exactly as sent, so it can check the sender's
/// signature itself (see `WebhookSignature`). Not in the generated client:
/// apps never call it, the third party does.
@ExcludeFromClient()
@BlackList()
@Controller('hooks')
class HookController {
  const HookController({required this.webhookHandler});

  final WebhookHandler webhookHandler;

  @WebhookRateLimit()
  @Post(':name')
  Future<void> handle({
    @Param() required String name,
    @Ip() required String ipAddress,
    @Body() required Stream<List<int>> body,
    required RequestHeaders headers,
    required Response response,
  }) async {
    await webhookHandler.handle(
      name: name,
      body: body,
      headers: headers,
      ipAddress: ipAddress,
      response: response,
    );
  }
}
