import 'dart:io';
import 'dart:typed_data';

import 'package:revali_router/revali_router.dart';
import 'package:zonai/deps.dart';

class WebhookHandler {
  const WebhookHandler();

  /// Answers through [response]: a `String` body goes out as `text/plain`,
  /// where returning bytes would be sent as a file attachment.
  Future<void> handle({
    required String name,
    required Stream<List<int>> body,
    required RequestHeaders headers,
    required String ipAddress,
    required Response response,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await body.forEach(bytes.add);

    final answer = await zonaiDB.runWebhook(
      name: name,
      body: bytes.takeBytes(),
      headers: _flatten(headers),
      ip: ipAddress,
    );

    if (!answer.found) {
      response.statusCode = HttpStatus.notFound;
      return;
    }

    response.statusCode = answer.status;
    if (answer.body case final String text) {
      await response.body.replace(text);
    }
  }

  /// Lower-cased names, as `WebhookSignature` reads them. A repeated header
  /// is joined with `, `, which is how HTTP folds them.
  Map<String, String> _flatten(RequestHeaders headers) {
    final flat = <String, String>{};
    headers.forEach((key, values) {
      flat[key.toLowerCase()] = values.join(', ');
    });
    return flat;
  }
}
