// See mrgnhnt96/zonai#2 for the design rationale.

/// Trust configuration for a JWT issued by an external identity provider.
sealed class ExternalIdpConfig {
  const ExternalIdpConfig();

  factory ExternalIdpConfig.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      SharedSecretIdpConfig._type => SharedSecretIdpConfig.fromJson(json),
      JwksIdpConfig._type => JwksIdpConfig.fromJson(json),
      final t => throw ArgumentError.value(
        t,
        'type',
        'Unknown external IdP type',
      ),
    };
  }

  String get issuer;
  String get audience;
  String get authTable;
  String get type;

  Map<String, Object?> toJson() => {'type': type};
}

/// Configuration for an IdP that signs tokens with a shared HMAC secret.
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

  static const _type = 'shared_secret';

  @override
  final String issuer;
  @override
  final String audience;
  @override
  final String authTable;

  /// HMAC secret used to verify token signatures.
  final String secret;

  @override
  String get type => _type;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'issuer': issuer,
    'audience': audience,
    'authTable': authTable,
    'secret': secret,
  };
}

/// Configuration for an IdP that publishes its public keys via JWKS.
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

  static const _type = 'jwks';

  @override
  final String issuer;
  @override
  final String audience;
  @override
  final String authTable;

  /// URL of the JWKS endpoint.
  final String jwksUrl;

  /// How long a JWKS response is reused before being re-fetched.
  final Duration cacheTtl;

  /// Maximum time to wait for a JWKS fetch on a cold cache.
  final Duration fetchTimeout;

  @override
  String get type => _type;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'issuer': issuer,
    'audience': audience,
    'authTable': authTable,
    'jwksUrl': jwksUrl,
    'cacheTtlSeconds': cacheTtl.inSeconds,
    'fetchTimeoutSeconds': fetchTimeout.inSeconds,
  };
}
