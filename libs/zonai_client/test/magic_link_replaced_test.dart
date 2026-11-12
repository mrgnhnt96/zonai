import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai_client/zonai_client.dart';

/// #124: the body `apps/server`'s exception catcher sends for a magic link a
/// newer link replaced, and the type a caller catches for it.
void main() {
  ServerException fromServer(Map<String, Object?> body) =>
      ServerException.fromBody(
        message: 'Unauthorized',
        statusCode: 401,
        body: jsonEncode(body),
      );

  test('the magic_link_replaced envelope becomes the typed exception', () {
    final replaced = MagicLinkReplacedException.tryFrom(
      fromServer({
        'error': {
          'code': 'magic_link_replaced',
          'message': 'This magic link was replaced by a newer one',
        },
      }),
    );

    expect(replaced, isNotNull);
    expect(replaced!.message, 'This magic link was replaced by a newer one');
    expect(MagicLinkReplacedException.code, 'magic_link_replaced');
  });

  // An invalid or expired link is still the bare-sentence 401. It must stay a
  // ServerException, or a caller would send the user to an email that holds
  // no working link.
  test('any other 401 stays a ServerException', () {
    expect(
      MagicLinkReplacedException.tryFrom(
        fromServer({'error': 'Invalid or expired magic link code'}),
      ),
      isNull,
    );
  });
}
