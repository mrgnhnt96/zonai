import 'package:test/test.dart';
import 'package:zonai_server/components/lifecycle_components/trace_id.dart';

/// Design §4 item 7: "Secrets, codes, tokens and `state` never reach the
/// logger, error messages, or the swagger surface."
///
/// The logger half of that is a property of exactly one line — `Trace.wrap`
/// logs `'${method} ${uri}'` on every single request — and `uri` includes the
/// query string. Before [redactSensitiveQuery] existed, a completed OAuth
/// sign-in printed
///
///     [302] 41ms: GET /auth/oauth/callback/google?code=4/0Ab…&state=Xy7…
///
/// to the console for anyone running below `Level.info`, which includes
/// `--log request`, `--log trace` and `--log verbose` — and
/// `sip run playground serve` passes `--log verbose`. Both values in that
/// line are live for the next few minutes: the code exchanges for a session,
/// the state is the handle that binds the exchange.
void main() {
  group('redactSensitiveQuery', () {
    test('an OAuth callback loses its code and state', () {
      final result = redactSensitiveQuery(
        Uri.parse('/auth/oauth/callback/google?code=4%2F0AbCdEf&state=Xy7Zq'),
      );

      expect(result, isNot(contains('4/0AbCdEf')));
      expect(result, isNot(contains('4%2F0AbCdEf')));
      expect(result, isNot(contains('Xy7Zq')));
    });

    test('the shape of the request survives', () {
      // The diagnostic value of logging a URI is knowing which route was hit
      // with which parameters present. None of that needs the values.
      final result = redactSensitiveQuery(
        Uri.parse('/auth/oauth/callback/google?code=SECRET&state=SECRET2'),
      );

      expect(result, contains('/auth/oauth/callback/google'));
      expect(result, contains('code='));
      expect(result, contains('state='));
      expect(result, contains('redacted'));
    });

    test('a URI with no query is returned untouched', () {
      const path = '/auth/oauth/providers';
      expect(redactSensitiveQuery(Uri.parse(path)), path);
    });

    test('non-sensitive parameters keep their values', () {
      final result = redactSensitiveQuery(
        Uri.parse('/auth/oauth/start/google?table=users&redirect_to=%2Ftables'),
      );

      expect(result, contains('table=users'));
      expect(result, contains('redirect_to='));
      expect(result, contains('tables'));
    });

    test('a mixed request redacts only the sensitive half', () {
      final result = redactSensitiveQuery(
        Uri.parse('/auth/oauth/callback/google?code=SECRET&table=users'),
      );

      expect(result, isNot(contains('SECRET')));
      expect(result, contains('table=users'));
    });

    test('every token-shaped parameter name is covered', () {
      for (final key in const [
        'code',
        'state',
        'id_token',
        'access_token',
        'refresh_token',
        'token',
        'secret',
        'code_verifier',
        'client_secret',
      ]) {
        expect(
          redactSensitiveQuery(Uri.parse('/x?$key=LEAKED')),
          isNot(contains('LEAKED')),
          reason: '$key was logged in full',
        );
      }
    });

    test('a repeated sensitive key is redacted in every position', () {
      // `queryParameters` collapses repeats to the last value; rebuilding from
      // it would silently drop the earlier ones from the logged shape and,
      // worse, could leave one behind.
      final result = redactSensitiveQuery(
        Uri.parse('/x?code=FIRST&code=SECOND&table=users'),
      );

      expect(result, isNot(contains('FIRST')));
      expect(result, isNot(contains('SECOND')));
      expect(result, contains('table=users'));
    });

    test('an admin invite acceptance loses its token', () {
      // `GET /auth/admin/invite/oauth/start/:provider?token=` is the one route
      // that carries a raw admin-invite token in a query string, and the
      // admin-invite design's §4 item 8 is the same requirement in different
      // words: "the token never reaches a log". Checked here rather than
      // assumed from `token` already being in the denylist -- that list is
      // where the property lives, and this is the route that now depends on
      // it.
      final result = redactSensitiveQuery(
        Uri.parse(
          '/auth/admin/invite/oauth/start/google'
          '?token=a1b2c3d4e5f6&redirect_to=%2F_%2Fadmin%2Finvite',
        ),
      );

      expect(result, isNot(contains('a1b2c3d4e5f6')));
      // The shape survives: which route was hit, with which parameters
      // present, is the whole diagnostic value and none of the risk.
      expect(result, contains('/auth/admin/invite/oauth/start/google'));
      expect(result, contains('token='));
      expect(result, contains('redirect_to='));
    });

    test('an absolute URI keeps its origin', () {
      final result = redactSensitiveQuery(
        Uri.parse('https://api.example.com:8080/auth/oauth/callback/g?code=S'),
      );

      expect(result, startsWith('https://api.example.com:8080/'));
      expect(result, isNot(contains('code=S&')));
      expect(result, isNot(endsWith('code=S')));
    });
  });
}
