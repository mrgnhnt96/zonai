import 'package:zonai_schema/zonai_schema.dart';

BoomWebhook main() => const BoomWebhook();

/// Queues a write, then throws: the write must not commit.
final class BoomWebhook extends Webhook {
  const BoomWebhook() : super(name: 'boom');

  @override
  Future<WebhookResponse> handle(WebhookRequest request) async {
    mutate.create.one(tableName: 'posts', object: {'title': 'from-boom'});
    throw StateError('boom');
  }
}
