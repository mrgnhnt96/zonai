import 'package:test/test.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';

import 'package:zonai/src/utils/oauth/oauth_authorization_url_builder.dart';

void main() {
  group(buildOAuthAuthorizationUrl, () {
    test('includes PKCE params for a provider that uses PKCE (Google)', () {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      final url = buildOAuthAuthorizationUrl(
        provider: provider,
        redirectUri: 'https://app.example/auth/oauth/callback/google',
        state: 'state-123',
        codeChallenge: 'challenge-abc',
        nonce: 'nonce-xyz',
      );

      final uri = Uri.parse(url);
      expect(uri.origin, 'https://accounts.google.com');
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['client_id'], 'cid');
      expect(
        uri.queryParameters['redirect_uri'],
        'https://app.example/auth/oauth/callback/google',
      );
      expect(uri.queryParameters['scope'], 'openid email profile');
      expect(uri.queryParameters['state'], 'state-123');
      expect(uri.queryParameters['code_challenge'], 'challenge-abc');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['nonce'], 'nonce-xyz');
    });

    test('omits PKCE params for a provider that does not use PKCE (Apple)', () {
      final provider = OAuthProvider.apple(
        clientId: 'com.example.app',
        teamId: 'team',
        keyId: 'key',
        privateKey: 'pem',
      );

      final url = buildOAuthAuthorizationUrl(
        provider: provider,
        redirectUri: 'https://app.example/auth/oauth/callback/apple',
        state: 'state-123',
        codeChallenge: 'challenge-abc',
        nonce: 'nonce-xyz',
      );

      final uri = Uri.parse(url);
      expect(uri.queryParameters.containsKey('code_challenge'), isFalse);
      expect(uri.queryParameters.containsKey('code_challenge_method'), isFalse);
      // Apple is a verifiable OIDC issuer, so nonce is still included.
      expect(uri.queryParameters['nonce'], 'nonce-xyz');
    });

    test('omits nonce for a provider with no verifiable id_token (GitHub)', () {
      final provider = OAuthProvider.github(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      final url = buildOAuthAuthorizationUrl(
        provider: provider,
        redirectUri: 'https://app.example/auth/oauth/callback/github',
        state: 'state-123',
        codeChallenge: 'challenge-abc',
        nonce: 'nonce-xyz',
      );

      final uri = Uri.parse(url);
      expect(uri.queryParameters.containsKey('nonce'), isFalse);
      // GitHub does use PKCE, though.
      expect(uri.queryParameters['code_challenge'], 'challenge-abc');
    });

    test('joins multiple scopes with a single space', () {
      final provider = OAuthProvider.discord(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      final url = buildOAuthAuthorizationUrl(
        provider: provider,
        redirectUri: 'https://app.example/auth/oauth/callback/discord',
        state: 's',
        codeChallenge: 'c',
        nonce: 'n',
      );

      expect(Uri.parse(url).queryParameters['scope'], 'identify email');
    });

    test('sends response_mode=form_post for Apple, which rejects the '
        'request without it when name/email are in scope', () {
      final provider = OAuthProvider.apple(
        clientId: 'com.example.app',
        teamId: 'TEAM',
        keyId: 'KEY',
        privateKey: 'pem',
      );

      final url = buildOAuthAuthorizationUrl(
        provider: provider,
        redirectUri: 'https://app.example/auth/oauth/callback/apple',
        state: 's',
        codeChallenge: 'c',
        nonce: 'n',
      );

      expect(provider.scopes, contains('email'));
      expect(Uri.parse(url).queryParameters['response_mode'], 'form_post');
    });

    test('omits response_mode for providers that do not set one', () {
      final provider = OAuthProvider.google(
        clientId: 'cid',
        clientSecret: 'secret',
      );

      final url = buildOAuthAuthorizationUrl(
        provider: provider,
        redirectUri: 'https://app.example/auth/oauth/callback/google',
        state: 's',
        codeChallenge: 'c',
        nonce: 'n',
      );

      expect(
        Uri.parse(url).queryParameters.containsKey('response_mode'),
        isFalse,
      );
    });
  });
}
