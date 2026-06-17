import 'package:meta/meta.dart';

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

  /// Dotted path into the verified claims (e.g. `'role'`,
  /// `'app_metadata.is_admin'`). When set, the value at this path is
  /// compared to [adminClaimEquals] using `==`; matches mark the
  /// resolved [Jwt] as admin. Null (default) means external tokens
  /// never derive admin status from claims — use row-level rules on
  /// [authTable] instead.
  ///
  /// Equality semantics only. For list-membership checks (e.g.
  /// Cognito's `cognito:groups` array), implement an admin check at
  /// the row-rules layer.
  String? get adminClaimPath;

  /// Value compared against `claims[adminClaimPath]`. Required when
  /// [adminClaimPath] is set; ignored otherwise.
  Object? get adminClaimEquals;

  @mustCallSuper
  Map<String, Object?> toJson() => {
    'type': type,
    'issuer': issuer,
    'audience': audience,
    'authTable': authTable,
    if (adminClaimPath != null) 'adminClaimPath': adminClaimPath,
    if (adminClaimEquals != null) 'adminClaimEquals': adminClaimEquals,
  };
}

/// Configuration for an IdP that signs tokens with a shared HMAC secret.
final class SharedSecretIdpConfig extends ExternalIdpConfig {
  const SharedSecretIdpConfig({
    required this.issuer,
    required this.audience,
    required this.authTable,
    required this.secret,
    this.adminClaimPath,
    this.adminClaimEquals,
  });

  factory SharedSecretIdpConfig.fromJson(Map<String, dynamic> json) =>
      SharedSecretIdpConfig(
        issuer: json['issuer'] as String,
        audience: json['audience'] as String,
        authTable: json['authTable'] as String,
        secret: json['secret'] as String,
        adminClaimPath: json['adminClaimPath'] as String?,
        adminClaimEquals: json['adminClaimEquals'],
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
  final String? adminClaimPath;
  @override
  final Object? adminClaimEquals;

  @override
  String get type => _type;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'secret': secret};
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
    this.adminClaimPath,
    this.adminClaimEquals,
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
    adminClaimPath: json['adminClaimPath'] as String?,
    adminClaimEquals: json['adminClaimEquals'],
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
  final String? adminClaimPath;
  @override
  final Object? adminClaimEquals;

  @override
  String get type => _type;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'jwksUrl': jwksUrl,
    'cacheTtlSeconds': cacheTtl.inSeconds,
    'fetchTimeoutSeconds': fetchTimeout.inSeconds,
  };
}

/// Resolves the admin flag from verified IdP claims against [config].
/// Returns `false` when [ExternalIdpConfig.adminClaimPath] is null,
/// when the path doesn't resolve in [claims], or when the resolved
/// value does not `==` [ExternalIdpConfig.adminClaimEquals].
bool resolveAdminFromClaims(
  ExternalIdpConfig config,
  Map<String, Object?> claims,
) {
  final path = config.adminClaimPath;
  if (path == null) return false;
  final value = _walkClaimPath(claims, path);
  return value == config.adminClaimEquals;
}

Object? _walkClaimPath(Map<String, Object?> root, String dottedPath) {
  Object? current = root;
  for (final segment in dottedPath.split('.')) {
    if (current is! Map<String, Object?>) return null;
    current = current[segment];
  }
  return current;
}
