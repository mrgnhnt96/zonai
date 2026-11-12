import 'package:test/test.dart';
import 'package:zonai/deps.dart';

import '../routes/components/exception_catcher.dart';

/// #124: a magic link a newer link replaced answers with a code the client
/// can branch on (`MagicLinkReplacedException` in zonai_client), and stays a
/// 401 so a client that reads only the status treats it as before.
void main() {
  test('a replaced magic link renders the structured 401 envelope', () {
    final handled = const Exceptions()
        .onAuthException(const MagicLinkReplacedException())
        .asHandled;

    expect(handled.statusCode, 401);
    expect(handled.body, {
      'error': {
        'code': 'magic_link_replaced',
        'message': 'This magic link was replaced by a newer one',
      },
    });
  });
}
