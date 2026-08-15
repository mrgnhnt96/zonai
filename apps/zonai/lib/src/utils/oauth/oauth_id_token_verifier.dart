import '../../exceptions/auth_exception.dart';
import '../jwks_idp_verifier.dart';

/// Verifies an OIDC `id_token` for [provider] and checks its `nonce`
/// (design §3.1 step 2 / §4.3).
///
/// Signature, `iss`, `aud`, and `exp` are verified by [verifier] — a
/// [JwksIdpVerifier] built from [oauthJwksConfig] (`oauth_provider_credentials.dart`)
/// — so this only adds the `nonce` check OIDC's core spec requires and
/// [JwksIdpVerifier] doesn't know about (it's an external-IdP verifier, not
/// OAuth-specific). Reused rather than forked, per the design brief.
///
/// Throws [InvalidJwtException] — the same exception [verifier.verify]
/// itself throws for signature/iss/aud/exp failures — when the decoded
/// `nonce` claim doesn't equal [expectedNonce], so callers can catch one
/// exception type for "this id_token is not valid" regardless of which
/// check failed.
Future<Map<String, Object?>> verifyOAuthIdToken({
  required JwksIdpVerifier verifier,
  required String idToken,
  required String expectedNonce,
}) async {
  final claims = await verifier.verify(idToken);
  if (claims['nonce'] != expectedNonce) {
    throw const InvalidJwtException();
  }
  return claims;
}
