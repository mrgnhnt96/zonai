/// Where to find identity fields in a provider's `id_token` claims or
/// userinfo response. Every path is a bare key into that flat or nested
/// map — dotted for nested fields (e.g. Facebook's `'picture.data.url'`).
final class OAuthClaimMap {
  const OAuthClaimMap({
    required this.subject,
    required this.email,
    this.emailVerified,
    this.name,
    this.picture,
  });

  /// Stable per-provider user identifier. Combined with the provider id,
  /// this is the identity key `_oauth_identities` is unique on.
  final String subject;

  final String email;

  /// Path to a boolean verified-email claim. Null when the provider never
  /// asserts this — [OAuthLinking.byVerifiedEmail] then never links by
  /// email for that provider, only [OAuthLinking.always] can.
  final String? emailVerified;

  final String? name;

  final String? picture;
}
