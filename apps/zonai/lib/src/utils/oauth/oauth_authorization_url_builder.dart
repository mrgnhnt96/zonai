import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';

import 'oauth_provider_credentials.dart';

/// Builds the URL the user is redirected to for [provider]'s authorization
/// step (design §3.1 step 1).
///
/// [state] and, when [provider] uses PKCE, [codeChallenge] are always
/// included. [nonce] is only included when [provider] is a verifiable OIDC
/// issuer (`endpoints.issuer` set) — providers that never return an
/// `id_token` (GitHub, Discord, Facebook) have nothing to bind a nonce into.
String buildOAuthAuthorizationUrl({
  required OAuthProvider provider,
  required String redirectUri,
  required String state,
  required String codeChallenge,
  required String nonce,
}) {
  final base = Uri.parse(provider.endpoints.authorization);
  final params = <String, String>{
    ...base.queryParameters,
    'response_type': 'code',
    'client_id': oauthClientId(provider),
    'redirect_uri': redirectUri,
    'scope': provider.scopes.join(' '),
    'state': state,
    if (provider.usesPkce) ...{
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    },
    if (provider.endpoints.issuer != null) 'nonce': nonce,
  };
  return base.replace(queryParameters: params).toString();
}
