/// A successful response from a provider's token endpoint.
final class OAuthTokenResponse {
  const OAuthTokenResponse({
    required this.accessToken,
    this.idToken,
    this.tokenType = 'bearer',
    this.expiresIn,
    this.refreshToken,
    this.scope,
  });

  final String accessToken;

  /// Present only for OIDC providers (Google, Apple, Microsoft, GitLab,
  /// LinkedIn). Null for GitHub, Discord, and Facebook, which return no
  /// `id_token` — identity for those comes from the userinfo endpoint.
  final String? idToken;

  final String tokenType;
  final int? expiresIn;
  final String? refreshToken;
  final String? scope;
}
