import 'dart:convert';

/// Receives a third-party callback at `POST /hooks/<name>`.
///
/// The route is unauthenticated: anyone who knows the URL can call it, so a
/// handler checks the sender itself, usually with a [WebhookSignature] over
/// [WebhookRequest.body] and [WebhookRequest.headers].
///
/// [handle] runs as the server, like a cron job: `mutate` writes past
/// collection and row rules (admin-only tables included) and `email` sends.
/// Writes commit only once [handle] returns; a throw drops them and answers
/// 500.
///
/// ```dart
/// final class ResendWebhook extends Webhook {
///   const ResendWebhook() : super(name: 'resend');
///
///   @override
///   Future<WebhookResponse> handle(WebhookRequest request) async {
///     final signature = WebhookSignature(
///       Platform.environment['RESEND_WEBHOOK_SECRET']!,
///     );
///     if (!signature.isValid(request.body, request.headers)) {
///       return const WebhookResponse(401);
///     }
///
///     mutate.create.one(tableName: 'replies', object: {...});
///     return const WebhookResponse.ok();
///   }
/// }
///
/// Webhook main() => const ResendWebhook();
/// ```
abstract base class Webhook {
  const Webhook({required this.name});

  /// The `:name` in `POST /hooks/:name`.
  final String name;

  Future<WebhookResponse> handle(WebhookRequest request);
}

/// One delivery to a [Webhook], as it arrived.
final class WebhookRequest {
  const WebhookRequest({
    required this.body,
    required this.headers,
    required this.ip,
  });

  /// The body bytes exactly as received. Verify signatures against these,
  /// not against a re-encoded [json].
  final List<int> body;

  /// Request headers, names lower-cased, repeated headers joined with `, `.
  final Map<String, String> headers;

  /// The caller's address.
  final String ip;

  /// [body] decoded as UTF-8.
  String get text => utf8.decode(body, allowMalformed: true);

  /// [body] decoded as JSON. Throws a [FormatException] when it is not.
  Object? get json => jsonDecode(text);
}

/// What `POST /hooks/:name` answers with.
final class WebhookResponse {
  const WebhookResponse(this.status, {this.body});

  const WebhookResponse.ok({this.body}) : status = 200;

  final int status;

  /// Sent as `text/plain`. Senders rarely read it; it is for logs.
  final String? body;
}
