import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/zonai_schema.dart' show AuthType;
import 'package:zonai_server/src/exceptions/oauth_http_exception.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';

/// [AuthHandler]'s OAuth failure envelopes and payload mapping.
///
/// Every case below is decided *before* `zonaiDB` is touched -- which is
/// exactly why they are worth their own tests: they are the only OAuth
/// decisions this package makes on its own, and each one is a 4xx that would
/// otherwise have been a 500 from a null cast.
void main() {
  const handler = AuthHandler();

  group('completeOAuth failure envelopes', () {
    test(
      'a provider error is rejected before any exchange is attempted',
      () async {
        // No zonaiDB in scope. If this ever reached the db mutator the test
        // would die on a scoped-dep read instead of on the expected exception,
        // which is the point: the throw happens first.
        await expectLater(
          handler.completeOAuth(
            provider: 'google',
            code: null,
            state: null,
            error: 'access_denied',
          ),
          throwsA(isA<OAuthProviderRejectedException>()),
        );
      },
    );

    test('a missing code is reported as a missing code', () async {
      await expectLater(
        handler.completeOAuth(provider: 'google', code: null, state: 'abc'),
        throwsA(
          isA<OAuthCallbackIncompleteException>()
              .having((e) => e.hasCode, 'hasCode', isFalse)
              .having((e) => e.hasState, 'hasState', isTrue),
        ),
      );
    });

    test('a missing state is reported as a missing state', () async {
      await expectLater(
        handler.completeOAuth(provider: 'google', code: 'abc', state: null),
        throwsA(
          isA<OAuthCallbackIncompleteException>()
              .having((e) => e.hasCode, 'hasCode', isTrue)
              .having((e) => e.hasState, 'hasState', isFalse),
        ),
      );
    });

    test('an empty string counts as absent, not as a value', () async {
      // A provider that redirects with `?code=&state=` is malformed, not
      // holding a zero-length authorization code. Treating '' as present
      // would send it to the token endpoint and turn a 400 into a 500.
      await expectLater(
        handler.completeOAuth(provider: 'google', code: '', state: ''),
        throwsA(
          isA<OAuthCallbackIncompleteException>()
              .having((e) => e.hasCode, 'hasCode', isFalse)
              .having((e) => e.hasState, 'hasState', isFalse),
        ),
      );
    });

    test('an empty error string is not treated as a rejection', () async {
      // `?error=` with no value must not masquerade as a provider rejection;
      // it falls through to the incomplete-callback envelope.
      await expectLater(
        handler.completeOAuth(
          provider: 'google',
          code: null,
          state: null,
          error: '',
        ),
        throwsA(isA<OAuthCallbackIncompleteException>()),
      );
    });
  });

  group('failure envelopes leak nothing (design §4 item 7)', () {
    // These strings go into the 400 body AND into `Trace`'s error log, which
    // is two places a live authorization code must never reach.
    test('the rejection envelope names no code or state', () {
      const exception = OAuthProviderRejectedException(
        provider: 'google',
        error: 'access_denied',
      );

      expect('$exception', contains('google'));
      expect('$exception', contains('access_denied'));
    });

    test('the incomplete envelope names which field, never its value', () {
      const exception = OAuthCallbackIncompleteException(
        provider: 'google',
        hasCode: false,
        hasState: true,
      );

      expect('$exception', contains('code'));
      expect('$exception', isNot(contains('state:')));
    });

    test('a request body does not stringify its own credential', () {
      final idToken = OAuthBody.idToken(
        table: 'users',
        provider: 'google',
        idToken: 'header.SECRETPAYLOAD.sig',
      );
      final code = OAuthBody.code(
        table: 'users',
        provider: 'google',
        code: 'SECRETCODE',
        codeVerifier: 'SECRETVERIFIER',
        redirectUri: 'com.example.app:/cb',
      );

      expect('$idToken', isNot(contains('SECRETPAYLOAD')));
      expect('$code', isNot(contains('SECRETCODE')));
      expect('$code', isNot(contains('SECRETVERIFIER')));
      // The shape is still legible, which is the whole point of overriding
      // toString rather than deleting the information.
      expect('$idToken', contains('users'));
      expect('$idToken', contains('google'));
    });

    test('a callback body does not stringify its code or state', () {
      final body = OAuthCallbackBody.fromJson({
        'code': 'SECRETCODE',
        'state': 'SECRETSTATE',
      });

      expect('$body', isNot(contains('SECRETCODE')));
      expect('$body', isNot(contains('SECRETSTATE')));
      expect('$body', contains('<redacted>'));
    });

    test('toJson still round-trips -- redaction is toString only', () {
      // The Dart client has to be able to serialize this. Redacting the
      // serializer instead of the formatter would break the flow it protects.
      final body = OAuthBody.code(
        table: 'users',
        provider: 'google',
        code: 'c',
        codeVerifier: 'v',
        redirectUri: 'r',
      );

      final round = OAuthBody.fromJson(body.toJson());

      expect(round, isA<OAuthCodeBody>());
      expect((round as OAuthCodeBody).code, 'c');
      expect(round.codeVerifier, 'v');
      expect(round.redirectUri, 'r');
    });
  });

  group('nativeOAuthPayloadFor', () {
    test('an idToken body becomes an idToken payload', () {
      final payload = nativeOAuthPayloadFor(
        OAuthBody.idToken(table: 'users', provider: 'google', idToken: 'a.b.c'),
      );

      expect(payload.provider, 'google');
      expect(payload.idToken, 'a.b.c');
      expect(payload.code, isNull);
      expect(payload.codeVerifier, isNull);
      expect(payload.redirectUri, isNull);
    });

    test('a code body becomes a code payload', () {
      final payload = nativeOAuthPayloadFor(
        OAuthBody.code(
          table: 'users',
          provider: 'apple',
          code: 'the-code',
          codeVerifier: 'the-verifier',
          redirectUri: 'com.example.app:/cb',
        ),
      );

      expect(payload.provider, 'apple');
      expect(payload.code, 'the-code');
      expect(payload.codeVerifier, 'the-verifier');
      expect(payload.redirectUri, 'com.example.app:/cb');
      // Both-at-once is what `_nativeOAuth` rejects with an ArgumentError, so
      // this side must never produce it.
      expect(payload.idToken, isNull);
    });

    test('the payload is an oauth payload, not a password one', () {
      final payload = nativeOAuthPayloadFor(
        OAuthBody.idToken(table: 'users', provider: 'google', idToken: 'a.b.c'),
      );

      expect(payload, isA<NativeOAuthAuthPayload>());
      expect(payload.authType, AuthType.oauth);
    });
  });

  group('OAuthBody.fromJson', () {
    test('infers the shape when type is omitted', () {
      expect(
        OAuthBody.fromJson({
          'table': 'users',
          'provider': 'google',
          'idToken': 'a.b.c',
        }),
        isA<OAuthIdTokenBody>(),
      );
      expect(
        OAuthBody.fromJson({
          'table': 'users',
          'provider': 'google',
          'code': 'c',
          'codeVerifier': 'v',
          'redirectUri': 'r',
        }),
        isA<OAuthCodeBody>(),
      );
    });

    test('rejects a body carrying neither shape', () {
      // Previously the class of bug that produced an HTTP 500 from a null
      // cast on the other auth bodies -- see AuthBody.fromJson's own comment.
      expect(
        () => OAuthBody.fromJson({'table': 'users', 'provider': 'google'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a code body missing its PKCE half', () {
      expect(
        () => OAuthBody.fromJson({
          'table': 'users',
          'provider': 'google',
          'code': 'c',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty idToken rather than sending it to be verified', () {
      expect(
        () => OAuthBody.fromJson({
          'table': 'users',
          'provider': 'google',
          'idToken': '',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('filterOAuthProviders', () {
    const providers = [
      OAuthProviderPublic(
        id: 'google',
        displayName: 'Google',
        table: 'users',
        kind: OAuthProviderKind.google,
        startPath: '/auth/oauth/start/google?table=users',
      ),
      OAuthProviderPublic(
        id: 'github',
        displayName: 'GitHub',
        table: 'staff',
        kind: OAuthProviderKind.github,
        startPath: '/auth/oauth/start/github?table=staff',
      ),
    ];

    test('null means every collection, not none', () {
      expect(filterOAuthProviders(providers, null), hasLength(2));
    });

    test('an unknown table yields an empty list, not everything', () {
      expect(filterOAuthProviders(providers, 'nope'), isEmpty);
    });

    test('matches the table exactly', () {
      expect(filterOAuthProviders(providers, 'user'), isEmpty);
      expect(filterOAuthProviders(providers, 'users').single['id'], 'google');
    });
  });
}
