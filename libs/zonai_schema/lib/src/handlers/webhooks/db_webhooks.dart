import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/src/handlers/messages/message_io.dart';
import 'package:zonai_schema/src/handlers/webhooks/webhook_message.dart';
import 'package:zonai_schema/src/webhooks/webhook.dart';

/// The webhooks worker: runs the app's [Webhook]s for `POST /hooks/:name`.
class DbWebhooks {
  DbWebhooks({required List<Webhook> webhooks}) : webhooks = _byName(webhooks);

  final Map<String, Webhook> webhooks;

  static Map<String, Webhook> _byName(List<Webhook> webhooks) {
    final map = <String, Webhook>{};
    for (final webhook in webhooks) {
      if (map[webhook.name] case final existing?) {
        throw StateError(
          'Two webhooks are named "${webhook.name}": '
          '${existing.runtimeType} and ${webhook.runtimeType}',
        );
      }
      map[webhook.name] = webhook;
    }
    return map;
  }

  void start({MessageIo? io}) {
    MessageHandler(
      fromUnknownRequest: HandleWebhookRequest.fromRequest,
      onMessage: dispatch,
      io: io,
    ).listen();
  }

  /// Runs inside the handler's `runWithParent`, so `mutate` and `email`
  /// called from [Webhook.handle] belong to [request] and commit when this
  /// answers. A throw becomes a [MessageErrorResponse] and the writes are
  /// dropped.
  Future<Response?> dispatch(HandleWebhookRequest request) async {
    final webhook = webhooks[request.name];
    if (webhook == null) {
      return HandleWebhookResponse(id: request.id, found: false, status: 404);
    }

    final response = await webhook.handle(
      WebhookRequest(
        body: request.body,
        headers: request.headers,
        ip: request.ip,
      ),
    );

    return HandleWebhookResponse(
      id: request.id,
      found: true,
      status: response.status,
      body: response.body,
    );
  }
}
