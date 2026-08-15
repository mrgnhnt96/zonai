/// The URLs an OAuth2/OIDC provider exposes for the authorization-code
/// flow.
///
/// [userInfo], [issuer] and [jwks] are all optional because not every
/// provider is a full OIDC issuer: GitHub and Discord return neither an
/// `id_token` nor publish JWKS, and Apple publishes JWKS but no userinfo
/// endpoint (identity comes from the `id_token` alone).
final class OAuthEndpoints {
  const OAuthEndpoints({
    required this.authorization,
    required this.token,
    this.userInfo,
    this.issuer,
    this.jwks,
  });

  /// Where the user is redirected to grant consent.
  final String authorization;

  /// Where an authorization `code` is exchanged for tokens.
  final String token;

  /// Where the access token is exchanged for profile claims. Null for
  /// providers whose identity comes entirely from the `id_token`, or that
  /// require a provider-specific endpoint shape handled at the runtime
  /// layer (e.g. GitHub's `/user` + `/user/emails`).
  final String? userInfo;

  /// Expected `iss` claim. Set only when the provider issues a verifiable
  /// `id_token` — its presence is what tells the runtime layer to verify
  /// one via [jwks].
  final String? issuer;

  /// JWKS endpoint used to verify `id_token` signatures. Set only alongside
  /// [issuer].
  final String? jwks;
}
