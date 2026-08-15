/// Typed failures from the OAuth protocol machinery in `utils/oauth/`.
///
/// A separate hierarchy from [AuthException] (`exceptions/auth_exception.dart`)
/// rather than a new branch of it — `AuthException` is `sealed` and its direct
/// subtypes all live in that file, so a second library can't extend it.
/// Reuses [InvalidJwtException] directly (a concrete leaf, not sealed) for
/// `id_token` failures, since those are exactly what it already means.
sealed class OAuthException implements Exception {
  const OAuthException();
}

/// A provider's token or userinfo endpoint returned an OAuth2 error envelope
/// (`{"error": "...", "error_description": "..."}`) instead of a success
/// response.
final class OAuthProviderErrorException extends OAuthException {
  const OAuthProviderErrorException({
    required this.error,
    this.errorDescription,
  });

  final String error;
  final String? errorDescription;

  @override
  String toString() => errorDescription == null
      ? 'OAuth provider error: $error'
      : 'OAuth provider error: $error ($errorDescription)';
}

/// A provider endpoint returned a response that isn't a recognizable OAuth2
/// error envelope and can't be parsed as the expected success shape either
/// (non-JSON body, missing `access_token`, non-200 with no `error` field,
/// unreachable endpoint).
final class OAuthResponseException extends OAuthException {
  const OAuthResponseException(this.reason);

  final String reason;

  @override
  String toString() => 'Malformed OAuth response: $reason';
}

/// A provider has neither an `id_token` to verify nor a `userInfo` endpoint
/// to call, so identity cannot be resolved — or a claim map's `subject` path
/// didn't resolve to a non-empty string in the claims/userinfo payload.
final class OAuthIdentityUnresolvedException extends OAuthException {
  const OAuthIdentityUnresolvedException(this.reason);

  final String reason;

  @override
  String toString() => 'Could not resolve OAuth identity: $reason';
}

/// Apple's `.p8` private key could not be parsed, or signing the client
/// secret failed.
final class OAuthAppleSigningException extends OAuthException {
  const OAuthAppleSigningException(this.reason);

  final String reason;

  @override
  String toString() => 'Apple client-secret signing failed: $reason';
}
