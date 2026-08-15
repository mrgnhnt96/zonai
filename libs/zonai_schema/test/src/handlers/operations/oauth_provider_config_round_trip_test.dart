import 'dart:convert';

import 'package:test/test.dart';
// The config response is deliberately NOT exported from the public barrel --
// it carries client secrets and must never be reachable from the dashboard or
// the Dart client. Reach it by src path, as its siblings' tests do.
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// [OAuthProviderConfigResponse] serializes the provider config field by
/// field rather than through a shared `toJson`, so a field added to
/// [OAuthEndpoints] and wired into only one side crosses the
/// operations-worker boundary as null and the flow fails at the provider,
/// far from the cause.
///
/// `responseMode` was added exactly that way and needed three edits to land.
/// These tests fail if any endpoint field stops surviving the trip.
void main() {
  group('OAuthProviderConfigResponse round trip', () {
    OAuthProvider? roundTrip(OAuthProvider provider) {
      final encoded = jsonEncode(
        OAuthProviderConfigResponse(id: 'op-1', provider: provider).toJson(),
      );
      return OAuthProviderConfigResponse.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      ).provider;
    }

    test('a built-in provider keeps every endpoint field', () {
      final apple = OAuthProvider.apple(
        clientId: 'com.example.app',
        teamId: 'TEAM',
        keyId: 'KEY',
        privateKey: 'pem',
      );

      final result = roundTrip(apple)!;

      expect(result.endpoints.authorization, apple.endpoints.authorization);
      expect(result.endpoints.token, apple.endpoints.token);
      expect(result.endpoints.userInfo, apple.endpoints.userInfo);
      expect(result.endpoints.issuer, apple.endpoints.issuer);
      expect(result.endpoints.jwks, apple.endpoints.jwks);
      // The one that was missing. Without it Apple rejects the authorization
      // request, and the callback POST route is never reached.
      expect(result.endpoints.responseMode, 'form_post');
    });

    test('a custom provider keeps every endpoint field', () {
      final custom = OAuthProvider.custom(
        id: 'acme',
        displayName: 'Acme SSO',
        endpoints: const OAuthEndpoints(
          authorization: 'https://sso.acme.test/authorize',
          token: 'https://sso.acme.test/token',
          userInfo: 'https://sso.acme.test/userinfo',
          issuer: 'https://sso.acme.test',
          jwks: 'https://sso.acme.test/.well-known/jwks.json',
          responseMode: 'form_post',
        ),
        scopes: const ['openid', 'email'],
        claims: const OAuthClaimMap(subject: 'sub', email: 'email'),
        clientId: 'cid',
        clientSecret: 'secret',
      );

      final result = roundTrip(custom)!;

      expect(result.endpoints.authorization, custom.endpoints.authorization);
      expect(result.endpoints.token, custom.endpoints.token);
      expect(result.endpoints.userInfo, custom.endpoints.userInfo);
      expect(result.endpoints.issuer, custom.endpoints.issuer);
      expect(result.endpoints.jwks, custom.endpoints.jwks);
      expect(result.endpoints.responseMode, 'form_post');
    });

    test(
      'a provider with no response mode round trips as null, not "null"',
      () {
        final google = OAuthProvider.google(
          clientId: 'cid',
          clientSecret: 'secret',
        );

        expect(roundTrip(google)!.endpoints.responseMode, isNull);
      },
    );
  });
}
