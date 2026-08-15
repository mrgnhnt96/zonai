import 'package:zonai_schema/src/config/external_idp_config.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';

/// The `client_id` this provider authenticates as. Both concrete
/// [OAuthProvider] shapes carry one; only the base sealed type doesn't
/// expose it directly, since Apple's `clientId` lives alongside `teamId`/
/// `keyId`/`privateKey` rather than a shared `clientSecret`.
String oauthClientId(OAuthProvider provider) => switch (provider) {
  BuiltInOAuthProvider p => p.clientId,
  CustomOAuthProvider p => p.clientId,
};

/// The [JwksIdpConfig] used to verify [provider]'s `id_token`s via
/// [JwksIdpVerifier] (`utils/jwks_idp_verifier.dart`) — reused rather than
/// forked, per the design brief. Returns null when the provider isn't a
/// verifiable OIDC issuer (no [OAuthEndpoints.issuer] / [OAuthEndpoints.jwks],
/// e.g. GitHub, Discord, Facebook); callers fall back to the userinfo
/// endpoint instead.
JwksIdpConfig? oauthJwksConfig(OAuthProvider provider) {
  final issuer = provider.endpoints.issuer;
  final jwks = provider.endpoints.jwks;
  if (issuer == null || jwks == null) return null;
  return JwksIdpConfig(
    issuer: issuer,
    audience: oauthClientId(provider),
    // Unused by JwksIdpVerifier itself (only issuer/audience/jwksUrl are);
    // JwksIdpConfig requires a non-null value, so the provider id stands in.
    authTable: provider.id,
    jwksUrl: jwks,
  );
}
