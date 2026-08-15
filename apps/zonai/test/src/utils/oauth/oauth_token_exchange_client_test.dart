import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';

import 'package:zonai/src/utils/oauth/apple_client_secret_signer.dart';
import 'package:zonai/src/utils/oauth/oauth_exception.dart';
import 'package:zonai/src/utils/oauth/oauth_token_exchange_client.dart';

const _appleTestPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgFbgeH0A1XSR6v1QR
JnZFXZx0grlUHDXyjtG0/3WrqtWhRANCAAQXcjok5AXJsDSs0JnEZqAVvTp2wl1Z
B4cAe3piuRoFVz26mIS3EAQNUKkU5eEnggM3go9IX8fRu5Y8pkHg0O7L
-----END PRIVATE KEY-----
''';

void main() {
  group(OAuthTokenExchangeClient, () {
    test('parses a happy-path token response', () async {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'shh',
      );
      final client = OAuthTokenExchangeClient(
        httpClient: MockClient((req) async {
          expect(req.url.toString(), provider.endpoints.token);
          expect(req.headers['Accept'], 'application/json');
          final body = Uri(query: req.body).queryParameters;
          expect(body['grant_type'], 'authorization_code');
          expect(body['code'], 'auth-code');
          expect(body['client_id'], 'cid');
          expect(body['client_secret'], 'shh');
          expect(body['code_verifier'], 'verifier-value');
          expect(
            body['redirect_uri'],
            'https://app.example/auth/oauth/callback/google',
          );
          return http.Response(
            jsonEncode({
              'access_token': 'at-123',
              'id_token': 'idtok-abc',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'refresh_token': 'rt-456',
              'scope': 'openid email profile',
            }),
            200,
          );
        }),
      );

      final result = await client.exchangeCode(
        provider: provider,
        code: 'auth-code',
        redirectUri: 'https://app.example/auth/oauth/callback/google',
        codeVerifier: 'verifier-value',
      );

      expect(result.accessToken, 'at-123');
      expect(result.idToken, 'idtok-abc');
      expect(result.tokenType, 'Bearer');
      expect(result.expiresIn, 3600);
      expect(result.refreshToken, 'rt-456');
      expect(result.scope, 'openid email profile');
    });

    test('sends Accept: application/json so GitHub returns JSON instead of its '
        'default url-encoded body', () async {
      final provider = OAuthProvider.github(
        clientId: 'cid',
        clientSecret: 'shh',
      );
      var acceptHeaderSeen = '';
      final client = OAuthTokenExchangeClient(
        httpClient: MockClient((req) async {
          acceptHeaderSeen = req.headers['Accept'] ?? '';
          return http.Response(
            jsonEncode({'access_token': 'gho_abc', 'token_type': 'bearer'}),
            200,
          );
        }),
      );

      await client.exchangeCode(
        provider: provider,
        code: 'c',
        redirectUri: 'https://app.example/auth/oauth/callback/github',
      );

      expect(acceptHeaderSeen, 'application/json');
    });

    test(
      'throws OAuthProviderErrorException for the provider error envelope',
      () async {
        final provider = OAuthProvider.google(
          clientId: 'cid',
          clientSecret: 'shh',
        );
        final client = OAuthTokenExchangeClient(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': 'invalid_grant',
                'error_description': 'Code was already redeemed.',
              }),
              400,
            ),
          ),
        );

        await expectLater(
          client.exchangeCode(
            provider: provider,
            code: 'used-code',
            redirectUri: 'https://app.example/auth/oauth/callback/google',
          ),
          throwsA(
            isA<OAuthProviderErrorException>()
                .having((e) => e.error, 'error', 'invalid_grant')
                .having(
                  (e) => e.errorDescription,
                  'errorDescription',
                  'Code was already redeemed.',
                ),
          ),
        );
      },
    );

    test('throws OAuthResponseException for a non-JSON body', () async {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'shh',
      );
      final client = OAuthTokenExchangeClient(
        httpClient: MockClient(
          (_) async => http.Response('access_token=at&token_type=bearer', 200),
        ),
      );

      await expectLater(
        client.exchangeCode(
          provider: provider,
          code: 'c',
          redirectUri: 'https://app.example/auth/oauth/callback/google',
        ),
        throwsA(isA<OAuthResponseException>()),
      );
    });

    test('throws OAuthResponseException when access_token is missing without '
        'an error envelope', () async {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'shh',
      );
      final client = OAuthTokenExchangeClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        ),
      );

      await expectLater(
        client.exchangeCode(
          provider: provider,
          code: 'c',
          redirectUri: 'https://app.example/auth/oauth/callback/google',
        ),
        throwsA(isA<OAuthResponseException>()),
      );
    });

    test('signs a fresh Apple client secret per exchange via the injected '
        'signer', () async {
      final provider = OAuthProvider.apple(
        clientId: 'com.example.app',
        teamId: 'TEAM',
        keyId: 'KID',
        privateKey: _appleTestPrivateKeyPem,
      );
      String? sentSecret;
      final client = OAuthTokenExchangeClient(
        appleClientSecretSigner: AppleClientSecretSigner(),
        httpClient: MockClient((req) async {
          final body = Uri(query: req.body).queryParameters;
          sentSecret = body['client_secret'];
          return http.Response(
            jsonEncode({'access_token': 'at', 'id_token': 'idtok'}),
            200,
          );
        }),
      );

      await withClock(Clock.fixed(DateTime.utc(2026, 1, 1)), () async {
        await client.exchangeCode(
          provider: provider,
          code: 'c',
          redirectUri: 'https://app.example/auth/oauth/callback/apple',
        );
      });

      expect(sentSecret, isNotNull);
      // Apple's secret is a three-segment JWT, not a static string.
      expect(sentSecret!.split('.'), hasLength(3));
    });

    test('throws StateError when exchanging an Apple code without an injected '
        'signer', () async {
      final provider = OAuthProvider.apple(
        clientId: 'com.example.app',
        teamId: 'TEAM',
        keyId: 'KID',
        privateKey: _appleTestPrivateKeyPem,
      );
      final client = OAuthTokenExchangeClient(
        httpClient: MockClient((_) async => http.Response(jsonEncode({}), 200)),
      );

      await expectLater(
        client.exchangeCode(
          provider: provider,
          code: 'c',
          redirectUri: 'https://app.example/auth/oauth/callback/apple',
        ),
        throwsStateError,
      );
    });
  });
}
