import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai_schema/src/handlers/webhooks/webhook_message.dart';

class WebhookMailman
    extends Mailman<HandleWebhookRequest, HandleWebhookResponse> {
  WebhookMailman()
    : super(
        debugName: debug,
        executablePath: settings.compiledWebhooksPath,
        fromJson: HandleWebhookResponse.fromJson,
      );

  static const debug = 'WEBHOOK';
}
