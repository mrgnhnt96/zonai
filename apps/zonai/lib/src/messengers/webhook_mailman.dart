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
        warmRequestTimeout: requestTimeout,
      );

  static const debug = 'WEBHOOK';

  /// Webhook handlers are app code and routinely call out (verifying a
  /// delivery, fetching the object it names), so the 1s default would fail
  /// ordinary deliveries. Senders give up on their own clock and retry, so
  /// waiting much past this buys nothing.
  static const requestTimeout = Duration(seconds: 30);
}
