import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_server/src/exceptions/oauth_http_exception.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';

import '../routes/controllers/auth_controller.dart';

/// Route-level tests for the OAuth HTTP surface (`docs/oauth-design.md` §3).
///
/// These drive [AuthController]'s methods directly against a real
/// [ResponseImpl] and a stub [AuthHandler]. That boundary is chosen because it
/// is the one this leaf owns and the one that can be wrong on its own: what
/// status code goes out, what lands in `Location`, what the session handoff
/// looks like, and which of `code`/`state`/`error` reaches the handler from
/// which transport. The flows behind [AuthHandler] belong to
/// `parts/auth/oauth.dart` and are tested there.
///
/// What this does NOT cover: that revali routes a real HTTP request to these
/// methods at all. That is generated code -- see `oauth_rate_limit_test.dart`,
/// which reads the generated route table when it is present.
void main() {
  group('GET /auth/oauth/providers', () {
    test(
      'returns every (table, provider) pair when no table is given',
      () async {
        final controller = AuthController(authHandler: _StubAuthHandler());

        final result = await controller.oauthProviders();

        expect(result.map((e) => '${e['table']}/${e['id']}'), [
          'users/google',
          'users/apple',
          'staff/google',
        ]);
      },
    );

    test('narrows to one collection when ?table= is given', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());

      final result = await controller.oauthProviders(table: 'staff');

      expect(result.map((e) => '${e['table']}/${e['id']}'), ['staff/google']);
    });

    test('carries no secret-shaped field', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());

      final result = await controller.oauthProviders();

      // Design §2.4 / §4 item 9. `toPublic()` is where the redaction actually
      // happens and zonai_schema tests it there; this pins that the HTTP
      // surface does not put anything back.
      for (final provider in result) {
        expect(
          provider.keys,
          isNot(
            anyElement(
              anyOf(
                contains('secret'),
                contains('Secret'),
                contains('privateKey'),
                contains('token'),
                equals('endpoints'),
              ),
            ),
          ),
        );
      }
    });
  });

  group('GET /auth/oauth/start/:provider', () {
    test('302s to the provider authorization URL', () async {
      final handler = _StubAuthHandler();
      final controller = AuthController(authHandler: handler);
      final response = _response();

      await controller.startOAuth(
        authorization: null,
        provider: 'google',
        table: 'users',
        redirectTo: '/tables',
        response: response,
      );

      expect(response.statusCode, HttpStatus.found);
      expect(
        response.headers.get(HttpHeaders.locationHeader),
        'https://provider.example/authorize?state=S',
      );
      expect(handler.startCalls, [
        (table: 'users', provider: 'google', redirectTo: '/tables'),
      ]);
    });

    test('puts nothing in the response body', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      await controller.startOAuth(
        authorization: null,
        provider: 'google',
        table: 'users',
        redirectTo: null,
        response: response,
      );

      // The authorization URL carries `state` and `code_challenge`. A copy in
      // the body would be a second place for them to be cached or logged.
      expect(response.body.isNull, isTrue);
    });

    test('does not mint a session', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      await controller.startOAuth(
        authorization: null,
        provider: 'google',
        table: 'users',
        redirectTo: null,
        response: response,
      );

      expect(response.headers.get('X-Auth'), isNull);
      expect(response.headers.get(HttpHeaders.setCookieHeader), isNull);
    });
  });

  group('GET /auth/admin/oauth/start/:provider', () {
    test('302s to the provider authorization URL', () async {
      final handler = _StubAuthHandler();
      final controller = AuthController(authHandler: handler);
      final response = _response();

      await controller.startAdminOAuth(
        authorization: null,
        provider: 'google',
        redirectTo: '/_/auth/oauth/callback',
        response: response,
      );

      expect(response.statusCode, HttpStatus.found);
      expect(
        response.headers.get(HttpHeaders.locationHeader),
        'https://provider.example/authorize?state=ADMIN',
      );
      expect(handler.adminStartCalls, [
        (provider: 'google', redirectTo: '/_/auth/oauth/callback'),
      ]);
    });

    test(
      'reaches startAdminOAuth, never the table-taking startOAuth',
      () async {
        // The whole point of the route. `startOAuth` mints a challenge flagged
        // `isAdmin: false`, whose callback auto-provisions a first-seen
        // identity -- and the collection this route resolves mixes in
        // `AsAdmin`, so a row provisioned there signs in as a full admin
        // (`_getJwtConfig`: `isAdmin: admin != null`, no per-row predicate).
        // Routing this to `startOAuth` with the admin table would reintroduce
        // exactly that.
        final handler = _StubAuthHandler();
        final controller = AuthController(authHandler: handler);

        await controller.startAdminOAuth(
          authorization: null,
          provider: 'google',
          redirectTo: null,
          response: _response(),
        );

        expect(handler.adminStartCalls, hasLength(1));
        expect(handler.startCalls, isEmpty);
      },
    );

    test('puts nothing in the response body and mints no session', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      await controller.startAdminOAuth(
        authorization: null,
        provider: 'google',
        redirectTo: null,
        response: response,
      );

      expect(response.body.isNull, isTrue);
      expect(response.headers.get('X-Auth'), isNull);
      expect(response.headers.get(HttpHeaders.setCookieHeader), isNull);
    });
  });

  group('GET /auth/oauth/callback/:provider', () {
    test('302s to the redirect_to recorded at start', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      await controller.oauthCallback(
        provider: 'google',
        code: 'the-code',
        state: 'the-state',
        error: null,
        response: response,
      );

      expect(response.statusCode, HttpStatus.found);
      expect(response.headers.get(HttpHeaders.locationHeader), '/tables');
    });

    test('falls back to / when the flow recorded no redirect_to', () async {
      final handler = _StubAuthHandler()..redirectTo = null;
      final controller = AuthController(authHandler: handler);
      final response = _response();

      await controller.oauthCallback(
        provider: 'google',
        code: 'the-code',
        state: 'the-state',
        error: null,
        response: response,
      );

      expect(response.headers.get(HttpHeaders.locationHeader), '/');
    });

    test('hands the session over as X-Auth and the dashboard cookie', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      await controller.oauthCallback(
        provider: 'google',
        code: 'the-code',
        state: 'the-state',
        error: null,
        response: response,
      );

      expect(response.headers.get('X-Auth'), 'the-jwt');

      final cookie = response.headers.get(HttpHeaders.setCookieHeader);
      expect(cookie, contains('zonai_auth_token=the-jwt'));
      expect(cookie, contains('Path=/'));
      expect(cookie, contains('SameSite=Lax'));
      // Not HttpOnly, deliberately: the dashboard's own client reads this
      // cookie back to attach to API calls (see ZonaiCookie's own doc).
      expect(cookie, isNot(contains('HttpOnly')));
    });

    test('never puts the session in the redirect URL', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      await controller.oauthCallback(
        provider: 'google',
        code: 'the-code',
        state: 'the-state',
        error: null,
        response: response,
      );

      // A token in a Location URL is written to every proxy log, browser
      // history entry and Referer header between here and the destination.
      expect(
        response.headers.get(HttpHeaders.locationHeader),
        isNot(contains('the-jwt')),
      );
    });

    test('a cancelled sign-in returns the browser to the recorded '
        'redirect_to, carrying the error code', () async {
      // `access_denied` is the user pressing Cancel -- a normal outcome, and
      // one that arrives mid-browser-redirect. A 400 JSON body is a dead end
      // there: the dashboard's callback screen already renders human copy for
      // this code and never got the chance to.
      final handler = _StubAuthHandler()
        ..abandonRedirectTo = '/_/auth/oauth/callback';
      final controller = AuthController(authHandler: handler);
      final response = _response();

      await controller.oauthCallback(
        provider: 'google',
        code: null,
        state: 'the-state',
        error: 'access_denied',
        response: response,
      );

      expect(response.statusCode, HttpStatus.found);
      expect(
        response.headers.get(HttpHeaders.locationHeader),
        '/_/auth/oauth/callback?error=access_denied',
      );
      // Nothing was minted, so nothing is handed over.
      expect(response.headers.get('X-Auth'), isNull);
      expect(response.headers.get(HttpHeaders.setCookieHeader), isNull);
    });

    test('the cancelled-flow redirect target comes from the challenge, not '
        'the callback', () async {
      // The destination is read back out of our own challenge row, where the
      // start route put it only after the open-redirect allowlist approved
      // it. A forged `state` that matches nothing yields no destination.
      final handler = _StubAuthHandler()..abandonRedirectTo = null;
      final controller = AuthController(authHandler: handler);

      await expectLater(
        controller.oauthCallback(
          provider: 'google',
          code: null,
          state: 'a-state-matching-no-challenge',
          error: 'access_denied',
          response: _response(),
        ),
        throwsA(isA<OAuthProviderRejectedException>()),
      );
    });

    test(
      'preserves the query string already on the recorded redirect_to',
      () async {
        final handler = _StubAuthHandler()
          ..abandonRedirectTo = '/_/auth/oauth/callback?from=tiles';
        final controller = AuthController(authHandler: handler);
        final response = _response();

        await controller.oauthCallback(
          provider: 'google',
          code: null,
          state: 'the-state',
          error: 'access_denied',
          response: response,
        );

        final location = Uri.parse(
          response.headers.get(HttpHeaders.locationHeader)!,
        );
        expect(location.path, '/_/auth/oauth/callback');
        expect(location.queryParameters, {
          'from': 'tiles',
          'error': 'access_denied',
        });
      },
    );

    test('passes the provider error through instead of exchanging', () async {
      final handler = _StubAuthHandler();
      final controller = AuthController(authHandler: handler);

      await expectLater(
        controller.oauthCallback(
          provider: 'google',
          code: null,
          state: null,
          error: 'access_denied',
          response: _response(),
        ),
        throwsA(isA<Exception>()),
      );

      expect(handler.completeCalls.single.error, 'access_denied');
    });
  });

  group('POST /auth/oauth/callback/:provider (Apple form_post)', () {
    test('reaches the handler with the same three values as the GET', () async {
      final getHandler = _StubAuthHandler();
      final postHandler = _StubAuthHandler();

      await AuthController(authHandler: getHandler).oauthCallback(
        provider: 'apple',
        code: 'c',
        state: 's',
        error: null,
        response: _response(),
      );
      await AuthController(authHandler: postHandler).oauthCallbackFormPost(
        provider: 'apple',
        body: OAuthCallbackBody.fromJson({
          'code': 'c',
          'state': 's',
          // Apple's first-authorization-only name blob. Accepted and ignored.
          'user': '{"name":{"firstName":"A","lastName":"B"}}',
        }),
        response: _response(),
      );

      expect(postHandler.completeCalls, getHandler.completeCalls);
    });

    test('302s exactly like the GET does', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      await controller.oauthCallbackFormPost(
        provider: 'apple',
        body: OAuthCallbackBody.fromJson({'code': 'c', 'state': 's'}),
        response: response,
      );

      expect(response.statusCode, HttpStatus.found);
      expect(response.headers.get(HttpHeaders.locationHeader), '/tables');
      expect(response.headers.get('X-Auth'), 'the-jwt');
    });

    test('carries a provider error the same way the GET does', () async {
      final handler = _StubAuthHandler();

      await expectLater(
        AuthController(authHandler: handler).oauthCallbackFormPost(
          provider: 'apple',
          body: OAuthCallbackBody.fromJson({
            'error': 'user_cancelled_authorize',
          }),
          response: _response(),
        ),
        throwsA(isA<Exception>()),
      );

      expect(handler.completeCalls.single.error, 'user_cancelled_authorize');
    });
  });

  group('POST /auth/oauth (native flow)', () {
    test('returns {accessToken, user} and sets X-Auth', () async {
      final controller = AuthController(authHandler: _StubAuthHandler());
      final response = _response();

      final result = await controller.oauth(
        body: OAuthBody.idToken(
          table: 'users',
          provider: 'google',
          idToken: 'header.payload.sig',
        ),
        headers: response.headers as ResponseHeaders,
      );

      expect(result, {
        'accessToken': 'the-jwt',
        'user': {'id': 'u1'},
      });
      expect(response.headers.get('X-Auth'), 'the-jwt');
    });

    test(
      'does not redirect -- the native flow has nowhere to send a browser',
      () async {
        final controller = AuthController(authHandler: _StubAuthHandler());
        final response = _response();

        await controller.oauth(
          body: OAuthBody.code(
            table: 'users',
            provider: 'google',
            code: 'c',
            codeVerifier: 'v',
            redirectUri: 'com.example.app:/cb',
          ),
          headers: response.headers as ResponseHeaders,
        );

        expect(response.statusCode, 200);
        expect(response.headers.get(HttpHeaders.locationHeader), isNull);
      },
    );
  });
}

ResponseImpl _response() => ResponseImpl(requestHeaders: HeadersImpl());

typedef _StartCall = ({String table, String provider, String? redirectTo});

/// No `table` field, because the route has no `table` parameter to record --
/// withholding it is the capability difference between the two start routes.
typedef _AdminStartCall = ({String provider, String? redirectTo});
typedef _CompleteCall = ({
  String provider,
  String? code,
  String? state,
  String? error,
});

/// Records what the controller asked for and answers with fixed values.
///
/// Extends the real [AuthHandler] rather than implementing an interface
/// because there is no interface -- and extending is what proves the
/// controller is calling the methods it would call in production, not a
/// parallel set that drifted.
class _StubAuthHandler extends AuthHandler {
  _StubAuthHandler();

  final startCalls = <_StartCall>[];
  final adminStartCalls = <_AdminStartCall>[];
  final completeCalls = <_CompleteCall>[];

  String? redirectTo = '/tables';

  /// What `ZonaiDb.abandonOAuth` would recover for the callback's `state`.
  /// `null` stands for "no consumable challenge matched", which is what a
  /// forged or replayed `state` produces.
  String? abandonRedirectTo;

  @override
  Future<List<Map<String, Object?>>> oauthProviders({String? table}) async {
    return filterOAuthProviders(const [
      OAuthProviderPublic(
        id: 'google',
        displayName: 'Google',
        table: 'users',
        kind: OAuthProviderKind.google,
        startPath: '/auth/oauth/start/google?table=users',
      ),
      OAuthProviderPublic(
        id: 'apple',
        displayName: 'Apple',
        table: 'users',
        kind: OAuthProviderKind.apple,
        startPath: '/auth/oauth/start/apple?table=users',
      ),
      OAuthProviderPublic(
        id: 'google',
        displayName: 'Google',
        table: 'staff',
        kind: OAuthProviderKind.google,
        startPath: '/auth/oauth/start/google?table=staff',
      ),
    ], table);
  }

  @override
  Future<String> startOAuth({
    required String table,
    required String provider,
    String? redirectTo,
    String? authorization,
  }) async {
    startCalls.add((table: table, provider: provider, redirectTo: redirectTo));
    return 'https://provider.example/authorize?state=S';
  }

  @override
  Future<String> startAdminOAuth({
    required String provider,
    String? redirectTo,
    String? authorization,
  }) async {
    adminStartCalls.add((provider: provider, redirectTo: redirectTo));
    return 'https://provider.example/authorize?state=ADMIN';
  }

  @override
  Future<({Map<String, Object?> user, String jwt, String? redirectTo})>
  completeOAuth({
    required String provider,
    required String? code,
    required String? state,
    String? error,
  }) async {
    completeCalls.add((
      provider: provider,
      code: code,
      state: state,
      error: error,
    ));
    // The provider-error arm is the one shape `super` cannot stand in for:
    // it now reaches `zonaiDB.abandonOAuth` to recover the destination the
    // flow recorded at start, and there is no database here. Throw the same
    // exception the real handler would, with [abandonRedirectTo] standing in
    // for what the challenge row held.
    if (error != null && error.isNotEmpty) {
      throw OAuthProviderRejectedException(
        provider: provider,
        error: error,
        redirectTo: abandonRedirectTo,
      );
    }
    // Delegate the envelope decisions to the real implementation so a stub
    // cannot quietly accept a callback the production path would reject;
    // `super` throws before it reaches zonaiDB on every failure shape.
    if (code == null || code.isEmpty || state == null || state.isEmpty) {
      return await super.completeOAuth(
        provider: provider,
        code: code,
        state: state,
        error: error,
      );
    }
    return (user: const {'id': 'u1'}, jwt: 'the-jwt', redirectTo: redirectTo);
  }

  @override
  Future<Map<String, Object?>> oauthNative(OAuthBody body) async {
    return {
      'accessToken': 'the-jwt',
      'user': const {'id': 'u1'},
    };
  }
}
