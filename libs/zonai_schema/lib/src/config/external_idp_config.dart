/// Configuration for trusting JWTs minted by external identity providers.
///
/// Lets a Zonai deployment accept tokens from a foreign IdP (Supabase Auth,
/// Auth0, Clerk, Cognito, Firebase Auth, custom OIDC, etc.) and map their
/// users into a Zonai-managed auth collection. The runtime side (verification,
/// auto-provisioning, `Jwt` construction from foreign claims) is layered on
/// top of this config and lives outside [zonai_schema].
///
/// This file ships only the schema-layer contract — the wire format for
/// configuring trust, the algorithm pinning each variant requires, and the
/// JSON round-trip. The runtime trust pipeline is a follow-up.
///
/// See mrgnhnt96/zonai#2 for the design rationale.
sealed class ExternalIdpConfig {
  const ExternalIdpConfig();

  /// Dispatch a JSON map to the matching concrete variant. Throws
  /// [ArgumentError] for unknown `kind` values so misconfiguration fails loudly
  /// at config-worker compile time rather than at request time.
  factory ExternalIdpConfig.fromJson(Map<String, dynamic> json) {
    return switch (json['kind']) {
      SharedSecretIdpConfig._kind => SharedSecretIdpConfig.fromJson(json),
      JwksIdpConfig._kind => JwksIdpConfig.fromJson(json),
      final k => throw ArgumentError.value(
        k,
        'kind',
        'Unknown external IdP kind',
      ),
    };
  }

  /// The `iss` claim that incoming tokens must declare. Verification rejects
  /// any token whose `iss` does not match exactly.
  String get issuer;

  /// The `aud` claim that incoming tokens must declare. Verification rejects
  /// any token whose `aud` does not match exactly.
  String get audience;

  /// The Zonai auth collection that users from this IdP map into. Provisioning,
  /// rule evaluation, and admin-claim derivation all key off this collection;
  /// the runtime auto-provisioning hook is registered on the matching auth
  /// table's extension class.
  String get authTable;

  /// Discriminator that identifies the concrete variant in JSON.
  String get kind;

  Map<String, dynamic> toJson();
}

/// Trust a JWT issuer that signs tokens with a shared HMAC secret.
///
/// Suitable for IdPs that publish a single symmetric secret (Supabase Auth,
/// many custom internal IdPs). The verifier pins HS256 — tokens whose `alg`
/// header is anything else are rejected, which closes the standard "alg=none"
/// and confused-deputy attacks.
///
/// For IdPs that publish public keys via JWKS, use [JwksIdpConfig].
final class SharedSecretIdpConfig extends ExternalIdpConfig {
  const SharedSecretIdpConfig({
    required this.issuer,
    required this.audience,
    required this.authTable,
    required this.secret,
  });

  factory SharedSecretIdpConfig.fromJson(Map<String, dynamic> json) =>
      SharedSecretIdpConfig(
        issuer: json['issuer'] as String,
        audience: json['audience'] as String,
        authTable: json['authTable'] as String,
        secret: json['secret'] as String,
      );

  static const _kind = 'shared_secret';

  @override
  final String issuer;
  @override
  final String audience;
  @override
  final String authTable;

  /// The shared HMAC secret used to verify token signatures. Treat as a
  /// production secret; configure via env-injected `String.fromEnvironment`.
  final String secret;

  @override
  String get kind => _kind;

  @override
  Map<String, dynamic> toJson() => {
    'kind': _kind,
    'issuer': issuer,
    'audience': audience,
    'authTable': authTable,
    'secret': secret,
  };
}

/// Trust a JWT issuer that publishes its public keys via JWKS.
///
/// Suitable for production IdPs that publish a rotating set of public keys at
/// a well-known URL (Auth0, Clerk, Cognito, Firebase Auth, any OIDC-compliant
/// provider). The verifier pins RS256/ES256 — tokens whose `alg` header is
/// anything else are rejected.
///
/// The runtime fetches [jwksUrl] on demand, caches the response for
/// [cacheTtl], and re-fetches when a token references an unknown `kid`. The
/// fetch path is bounded by [fetchTimeout] and circuit-breaks on repeated
/// failure so a degraded IdP does not amplify into a DoS on the auth path.
final class JwksIdpConfig extends ExternalIdpConfig {
  const JwksIdpConfig({
    required this.issuer,
    required this.audience,
    required this.authTable,
    required this.jwksUrl,
    this.cacheTtl = const Duration(hours: 1),
    this.fetchTimeout = const Duration(seconds: 2),
  });

  factory JwksIdpConfig.fromJson(Map<String, dynamic> json) => JwksIdpConfig(
    issuer: json['issuer'] as String,
    audience: json['audience'] as String,
    authTable: json['authTable'] as String,
    jwksUrl: json['jwksUrl'] as String,
    cacheTtl: json['cacheTtlSeconds'] == null
        ? const Duration(hours: 1)
        : Duration(seconds: json['cacheTtlSeconds'] as int),
    fetchTimeout: json['fetchTimeoutSeconds'] == null
        ? const Duration(seconds: 2)
        : Duration(seconds: json['fetchTimeoutSeconds'] as int),
  );

  static const _kind = 'jwks';

  @override
  final String issuer;
  @override
  final String audience;
  @override
  final String authTable;

  /// URL of the JWKS endpoint. Typically discoverable via
  /// `${issuer}/.well-known/openid-configuration`.
  final String jwksUrl;

  /// How long the runtime caches a JWKS response before re-fetching.
  final Duration cacheTtl;

  /// Maximum time the auth path will wait for a JWKS fetch on a cold cache
  /// before failing the request. Keeps a slow IdP from blocking auth.
  final Duration fetchTimeout;

  @override
  String get kind => _kind;

  @override
  Map<String, dynamic> toJson() => {
    'kind': _kind,
    'issuer': issuer,
    'audience': audience,
    'authTable': authTable,
    'jwksUrl': jwksUrl,
    'cacheTtlSeconds': cacheTtl.inSeconds,
    'fetchTimeoutSeconds': fetchTimeout.inSeconds,
  };
}
