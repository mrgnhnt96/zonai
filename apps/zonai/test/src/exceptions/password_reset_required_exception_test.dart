import 'package:test/test.dart';
import 'package:zonai/src/exceptions/auth_exception.dart';
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart';

/// The one invariant that keeps a bearer secret out of the logs.
///
/// `PasswordResetRequiredException` carries a token that lets whoever holds it
/// set the account's password. Two sinks in this codebase render an
/// exception's `toString` and neither renders a response body:
///
///  * `Exceptions._serverSide` logs `'Suppressed detail in client response:
///    $exception'` through a logger that persists to the `_log` TABLE;
///  * revali's `Router._logServerError` prints `'Request failed: $error'` for
///    any status >= 500 the application did not author, landing in the serve log
///    on disk. Since revali_router 5.1.2 an authored `5xx` reaches it only under
///    `debug`; an uncaught escape -- the case this test guards -- still logs.
///
/// Neither is on the intended 403 path today. This test is what keeps that
/// from mattering: it holds whether or not some future refactor routes auth
/// exceptions through `_serverSide`, and whether or not the exception ever
/// escapes uncaught. Guarding at the catcher instead would be one branch
/// protecting a value three other branches can still reach.
void main() {
  const token = 'c2VjcmV0LXZhbHVlOnVzZXJAZXhhbXBsZS5jb20=';

  const exception = PasswordResetRequiredException(
    token: token,
    expiresIn: Duration(minutes: 15),
    reason: PasswordResetReason.temporaryPassword,
  );

  group('toString never carries the token', () {
    test('the whole token is absent', () {
      expect('$exception', isNot(contains(token)));
    });

    // A future edit that renders the token's *decoded* halves would defeat the
    // check above while leaking exactly as much, so both are named here.
    test('neither decoded half leaks', () {
      expect('$exception', isNot(contains('secret-value')));
      expect('$exception', isNot(contains('user@example.com')));
    });

    test('it still says something useful', () {
      expect('$exception', contains('new password'));
    });
  });

  group('the fields the catcher reads are intact', () {
    // toString withholding the token is only safe because the catcher can
    // still reach it directly to build the 403's `details`.
    test('token, expiry and reason are readable', () {
      expect(exception.token, token);
      expect(exception.expiresIn, const Duration(minutes: 15));
      expect(exception.reason, PasswordResetReason.temporaryPassword);
    });
  });

  test('it is an AuthException, so the catcher must handle it', () {
    expect(exception, isA<AuthException>());
  });
}
