/// Typed view over the claim shape Supabase puts in its JWTs.
///
/// Anonymous Supabase sessions emit JWTs with `is_anonymous: true`,
/// `email: ""` (empty string sentinel — *not* missing), and
/// `phone: ""`. [SupabaseClaims] coerces empty strings to `null` so
/// the consumer can treat anonymous and missing-claim shapes
/// uniformly.
class SupabaseClaims {
  const SupabaseClaims({
    required this.sub,
    required this.isAnonymous,
    this.email,
    this.phone,
    this.role,
    this.appMetadata,
    this.userMetadata,
  });

  /// Builds a [SupabaseClaims] from the raw verified-claim map.
  ///
  /// Throws [ArgumentError] when `sub` is missing or not a non-empty
  /// String.
  factory SupabaseClaims.from(Map<String, Object?> claims) {
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty) {
      throw ArgumentError.value(
        sub,
        'claims["sub"]',
        'Supabase JWT is missing a non-empty "sub" claim',
      );
    }
    return SupabaseClaims(
      sub: sub,
      isAnonymous: claims['is_anonymous'] == true,
      email: _nonEmptyString(claims['email']),
      phone: _nonEmptyString(claims['phone']),
      role: _nonEmptyString(claims['role']),
      appMetadata: _mapOrNull(claims['app_metadata']),
      userMetadata: _mapOrNull(claims['user_metadata']),
    );
  }

  /// The Supabase `auth.users.id` UUID — keys the row in the
  /// configured `authTable`.
  final String sub;

  /// `true` when the session was created via
  /// [`signInAnonymously()`](https://supabase.com/docs/reference/dart/auth-signinanonymously)
  /// on the client. Anonymous users have no [email] or [phone].
  final bool isAnonymous;

  /// Verified email if one is on file, else `null`. Supabase uses the
  /// empty string for anonymous users; this getter normalizes that to
  /// `null` so callers don't have to.
  final String? email;

  /// Phone (E.164 format) if one is on file, else `null`. Same
  /// empty-string normalization as [email].
  final String? phone;

  /// `role` claim from the JWT. Supabase Auth puts `"authenticated"`
  /// here for normal user sessions; service-role tokens use
  /// `"service_role"`. This is **not** an admin signal — admin status
  /// is configured via `ExternalIdpConfig.adminClaimPath`.
  final String? role;

  /// Service-role-writable claims. Use this for `is_admin` /
  /// `is_maintainer` flags and any other privileged metadata you set
  /// from a trusted backend. Not writable by end-user clients.
  final Map<String, Object?>? appMetadata;

  /// User-writable claims via Supabase's
  /// [`updateUser`](https://supabase.com/docs/reference/dart/auth-updateuser)
  /// API. Treat as untrusted input from the client — fine for
  /// display-name-ish things, not for authorization decisions.
  final Map<String, Object?>? userMetadata;

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static Map<String, Object?>? _mapOrNull(Object? value) {
    if (value is! Map) return null;
    return value.cast<String, Object?>();
  }
}
