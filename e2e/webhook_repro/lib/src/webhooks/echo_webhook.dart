import 'package:zonai_schema/zonai_schema.dart';

EchoWebhook main() => const EchoWebhook();

/// Writes the body as a post's title -- `posts` creates are admin-only, so
/// the row proves the write ran as the server -- and answers with what it
/// was handed. Refuses a delivery without the `x-secret` header.
final class EchoWebhook extends Webhook {
  const EchoWebhook() : super(name: 'echo');

  @override
  Future<WebhookResponse> handle(WebhookRequest request) async {
    if (request.headers['x-secret'] != 'letmein') {
      return const WebhookResponse(401, body: 'bad secret');
    }

    mutate.create.one(tableName: 'posts', object: {'title': request.text});

    return WebhookResponse.ok(
      body: '${request.body.length} bytes from ${request.ip}',
    );
  }
}
