import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';

import 'package:zonai/src/utils/oauth/oauth_exception.dart';
import 'package:zonai/src/utils/oauth/oauth_userinfo_client.dart';

void main() {
  group(OAuthUserInfoClient, () {
    test(
      'fetches and decodes a generic provider\'s userinfo (GitHub)',
      () async {
        final provider = OAuthProvider.github(
          clientId: 'cid',
          clientSecret: 'secret',
        );
        final client = OAuthUserInfoClient(
          httpClient: MockClient((req) async {
            expect(req.url.toString(), 'https://api.github.com/user');
            expect(req.headers['Authorization'], 'Bearer at-123');
            return http.Response(
              jsonEncode({'id': 1, 'login': 'octocat', 'email': null}),
              200,
            );
          }),
        );

        final result = await client.fetch(
          provider: provider,
          accessToken: 'at-123',
        );
        expect(result['login'], 'octocat');
      },
    );

    test('appends fields=id,name,email,picture for Facebook, which otherwise '
        'returns only "name" by default', () async {
      final provider = OAuthProvider.facebook(
        clientId: 'cid',
        clientSecret: 'secret',
      );
      Uri? requestedUri;
      final client = OAuthUserInfoClient(
        httpClient: MockClient((req) async {
          requestedUri = req.url;
          return http.Response(
            jsonEncode({
              'id': 'fb-1',
              'name': 'A User',
              'email': 'a@example.com',
              'picture': {
                'data': {'url': 'https://fb.example/pic.jpg'},
              },
            }),
            200,
          );
        }),
      );

      await client.fetch(provider: provider, accessToken: 'at-123');

      expect(requestedUri, isNotNull);
      expect(requestedUri!.queryParameters['fields'], 'id,name,email,picture');
    });

    test(
      'does not append the fields param for non-Facebook providers',
      () async {
        final provider = OAuthProvider.discord(
          clientId: 'cid',
          clientSecret: 'secret',
        );
        Uri? requestedUri;
        final client = OAuthUserInfoClient(
          httpClient: MockClient((req) async {
            requestedUri = req.url;
            return http.Response(jsonEncode({'id': '1', 'username': 'u'}), 200);
          }),
        );

        await client.fetch(provider: provider, accessToken: 'at-123');

        expect(requestedUri!.queryParameters.containsKey('fields'), isFalse);
      },
    );

    test('throws OAuthIdentityUnresolvedException when provider has no '
        'userInfo endpoint (Apple)', () async {
      final provider = OAuthProvider.apple(
        clientId: 'com.example.app',
        teamId: 'team',
        keyId: 'key',
        privateKey: 'pem',
      );
      final client = OAuthUserInfoClient(
        httpClient: MockClient((_) async => http.Response('', 404)),
      );

      await expectLater(
        client.fetch(provider: provider, accessToken: 'at'),
        throwsA(isA<OAuthIdentityUnresolvedException>()),
      );
    });

    test('throws OAuthResponseException on a non-200 response', () async {
      final provider = OAuthProvider.github(
        clientId: 'cid',
        clientSecret: 'secret',
      );
      final client = OAuthUserInfoClient(
        httpClient: MockClient((_) async => http.Response('unauthorized', 401)),
      );

      await expectLater(
        client.fetch(provider: provider, accessToken: 'bad-token'),
        throwsA(isA<OAuthResponseException>()),
      );
    });
  });
}
