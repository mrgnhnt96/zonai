import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:zonai/src/utils/oauth/github_email_resolver.dart';
import 'package:zonai/src/utils/oauth/oauth_exception.dart';

void main() {
  group(GitHubEmailResolver, () {
    test('returns the primary verified email when /user/emails has one '
        '(the GET /user null-email fallback)', () async {
      final resolver = GitHubEmailResolver(
        httpClient: MockClient((req) async {
          expect(req.url.toString(), 'https://api.github.com/user/emails');
          expect(req.headers['Authorization'], 'Bearer gho_abc');
          return http.Response(
            jsonEncode([
              {
                'email': 'secondary@example.com',
                'primary': false,
                'verified': true,
              },
              {
                'email': 'primary@example.com',
                'primary': true,
                'verified': true,
              },
            ]),
            200,
          );
        }),
      );

      final email = await resolver.primaryVerifiedEmail('gho_abc');
      expect(email, 'primary@example.com');
    });

    test('does not treat an unverified primary email as usable '
        '(unverified must never be treated as verified)', () async {
      final resolver = GitHubEmailResolver(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'email': 'unverified@example.com',
                'primary': true,
                'verified': false,
              },
            ]),
            200,
          ),
        ),
      );

      final email = await resolver.primaryVerifiedEmail('gho_abc');
      expect(email, isNull);
    });

    test('returns null when no email is both primary and verified', () async {
      final resolver = GitHubEmailResolver(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'email': 'other@example.com',
                'primary': false,
                'verified': true,
              },
            ]),
            200,
          ),
        ),
      );

      expect(await resolver.primaryVerifiedEmail('gho_abc'), isNull);
    });

    test('throws OAuthResponseException on a non-200 response', () async {
      final resolver = GitHubEmailResolver(
        httpClient: MockClient((_) async => http.Response('forbidden', 403)),
      );

      await expectLater(
        resolver.primaryVerifiedEmail('bad-token'),
        throwsA(isA<OAuthResponseException>()),
      );
    });

    test('throws OAuthResponseException on a malformed body', () async {
      final resolver = GitHubEmailResolver(
        httpClient: MockClient((_) async => http.Response('not json', 200)),
      );

      await expectLater(
        resolver.primaryVerifiedEmail('gho_abc'),
        throwsA(isA<OAuthResponseException>()),
      );
    });
  });
}
