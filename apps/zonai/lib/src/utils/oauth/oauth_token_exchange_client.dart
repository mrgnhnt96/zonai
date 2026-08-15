import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider_kind.dart';

import 'apple_client_secret_signer.dart';
import 'oauth_exception.dart';
import 'oauth_provider_credentials.dart';
import 'oauth_token_response.dart';

/// Exchanges an authorization `code` for tokens at [OAuthEndpoints.token].
///
/// Injectable [http.Client] so tests never touch the network, exactly like
/// [JwksIdpVerifier] (`utils/jwks_idp_verifier.dart`).
///
/// **Runtime finding, not reflected in `docs/oauth-design.md` §2.3:**
/// GitHub's token endpoint defaults to a URL-encoded body
/// (`access_token=...&scope=...&token_type=...`), not JSON — it only
/// returns JSON when the request sends `Accept: application/json`
/// (confirmed against GitHub's "Authorizing OAuth apps" doc). This client
/// always sends that header so every provider's response can be parsed
/// uniformly.
final class OAuthTokenExchangeClient {
  OAuthTokenExchangeClient({
    http.Client? httpClient,
    AppleClientSecretSigner? appleClientSecretSigner,
  }) : _httpClient = httpClient ?? http.Client(),
       _appleClientSecretSigner = appleClientSecretSigner;

  final http.Client _httpClient;
  final AppleClientSecretSigner? _appleClientSecretSigner;

  /// Exchanges [code] at [provider]'s token endpoint.
  ///
  /// [codeVerifier] is required when [OAuthProvider.usesPkce] is true
  /// (design §4.2) and is the PKCE `code_verifier` generated alongside the
  /// `state`/`code_challenge` for this flow — never omit it for a
  /// PKCE-using provider, or the exchange degrades to an unauthenticated
  /// code swap.
  ///
  /// Throws [OAuthProviderErrorException] for the provider's `{error,
  /// error_description}` envelope, or [OAuthResponseException] for any
  /// other unparseable/failed response.
  Future<OAuthTokenResponse> exchangeCode({
    required OAuthProvider provider,
    required String code,
    required String redirectUri,
    String? codeVerifier,
  }) async {
    final clientSecret = await _clientSecretOf(provider);
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': oauthClientId(provider),
      'client_secret': clientSecret,
      if (codeVerifier != null) 'code_verifier': codeVerifier,
    };

    final http.Response response;
    try {
      response = await _httpClient.post(
        Uri.parse(provider.endpoints.token),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );
    } on Object catch (e) {
      throw OAuthResponseException('token endpoint request failed: $e');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on Object {
      throw OAuthResponseException(
        'token endpoint returned a non-JSON body (status '
        '${response.statusCode})',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw OAuthResponseException(
        'token endpoint returned a non-object body (status '
        '${response.statusCode})',
      );
    }

    if (decoded['error'] case final String error) {
      throw OAuthProviderErrorException(
        error: error,
        errorDescription: decoded['error_description'] as String?,
      );
    }

    final accessToken = decoded['access_token'];
    if (response.statusCode != 200 || accessToken is! String) {
      throw OAuthResponseException(
        'token endpoint response missing access_token (status '
        '${response.statusCode})',
      );
    }

    return OAuthTokenResponse(
      accessToken: accessToken,
      idToken: decoded['id_token'] as String?,
      tokenType: decoded['token_type'] as String? ?? 'bearer',
      expiresIn: (decoded['expires_in'] as num?)?.toInt(),
      refreshToken: decoded['refresh_token'] as String?,
      scope: decoded['scope'] as String?,
    );
  }

  Future<String> _clientSecretOf(OAuthProvider provider) {
    if (provider
        case BuiltInOAuthProvider(kind: OAuthProviderKind.apple) &&
            final apple) {
      final signer = _appleClientSecretSigner;
      if (signer == null) {
        throw StateError(
          'OAuthTokenExchangeClient needs an appleClientSecretSigner to '
          'exchange codes for an Apple provider',
        );
      }
      return Future.value(signer.sign(apple));
    }
    return switch (provider) {
      BuiltInOAuthProvider p => Future.value(p.clientSecret!),
      CustomOAuthProvider p => Future.value(p.clientSecret),
    };
  }
}
