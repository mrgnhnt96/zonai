import 'package:zonai_schema/src/config/external_idp_config.dart';

/// Helpers for trusting JWTs issued by Supabase Auth via the external-IdP
/// pipeline ([ExternalIdpConfig]). See `docs/external-idp-supabase.md`
/// for the platform walkthrough.
///
/// All factories are pure — they derive URLs from a `projectRef` and
/// return one of the existing [ExternalIdpConfig] variants. No
/// runtime, no network, no new dependencies in `zonai_schema`.
final class SupabaseExternalIdp {
  const SupabaseExternalIdp._();

  /// Builds a [JwksIdpConfig] for a Supabase project on the asymmetric
  /// JWT model (ECC / RSA signing keys + JWKS endpoint). Default for
  /// projects created after Supabase's asymmetric-JWT rollout.
  ///
  /// Pass the `app_metadata` path you flag maintainers / admins with —
  /// Supabase puts privileged claims under `app_metadata.*` by convention
  /// (writable from the service role only). Common shape:
  ///
  /// ```dart
  /// SupabaseExternalIdp.jwks(
  ///   projectRef: 'vshgjqqosbcoshzyznfq',
  ///   authTable: 'profiles',
  ///   adminClaimPath: 'app_metadata.is_admin',
  ///   adminClaimEquals: true,
  /// );
  /// ```
  ///
  /// Inspect under Supabase dashboard → Project Settings → API → JWT
  /// Keys. If the page shows a "Current Key" of ECC P-256 / RS256 /
  /// ES256 / etc., this is the right factory.
  ///
  /// [cacheTtl] / [fetchTimeout] pass through to [JwksIdpConfig]
  /// unchanged. Override the [audience] only when an upstream JWT
  /// hook mints tokens with a non-default `aud` — Supabase's standard
  /// user sessions always carry `aud: "authenticated"`.
  static JwksIdpConfig jwks({
    required String projectRef,
    required String authTable,
    String audience = 'authenticated',
    String? adminClaimPath,
    Object? adminClaimEquals,
    Duration cacheTtl = const Duration(hours: 1),
    Duration fetchTimeout = const Duration(seconds: 2),
  }) {
    _validateProjectRef(projectRef);
    return JwksIdpConfig(
      issuer: issuerFor(projectRef),
      audience: audience,
      authTable: authTable,
      jwksUrl: jwksUrlFor(projectRef),
      cacheTtl: cacheTtl,
      fetchTimeout: fetchTimeout,
      adminClaimPath: adminClaimPath,
      adminClaimEquals: adminClaimEquals,
    );
  }

  /// Builds a [SharedSecretIdpConfig] for a Supabase project still on
  /// the legacy HS256 shared-secret key model.
  ///
  /// Inspect under Supabase dashboard → Project Settings → API → JWT
  /// Keys. If the page shows only "Legacy HS256 (Shared Secret)" with
  /// no asymmetric "Current Key", this is the right factory. Newer
  /// projects don't have this — prefer [jwks].
  ///
  /// `secret` must be a compile-time-injected constant
  /// (`const String.fromEnvironment('SUPABASE_JWT_SECRET')`) — without
  /// the `const`, `fromEnvironment` returns the runtime default instead
  /// of the compile-time-injected value.
  ///
  /// Override [audience] only when an upstream JWT hook mints tokens
  /// with a non-default `aud`.
  static SharedSecretIdpConfig sharedSecret({
    required String projectRef,
    required String authTable,
    required String secret,
    String audience = 'authenticated',
    String? adminClaimPath,
    Object? adminClaimEquals,
  }) {
    _validateProjectRef(projectRef);
    return SharedSecretIdpConfig(
      issuer: issuerFor(projectRef),
      audience: audience,
      authTable: authTable,
      secret: secret,
      adminClaimPath: adminClaimPath,
      adminClaimEquals: adminClaimEquals,
    );
  }

  /// Supabase JWT `iss` claim for a project.
  static String issuerFor(String projectRef) =>
      'https://$projectRef.supabase.co/auth/v1';

  /// JWKS endpoint URL for a Supabase project.
  static String jwksUrlFor(String projectRef) =>
      '${issuerFor(projectRef)}/.well-known/jwks.json';

  /// Sanity check on the project ref: lowercase alphanumeric, ~20
  /// characters. Catches obvious mistakes (full URL passed by accident,
  /// trailing slash, etc.) at config time rather than at the first
  /// verification attempt.
  static void _validateProjectRef(String projectRef) {
    if (projectRef.isEmpty) {
      throw ArgumentError.value(projectRef, 'projectRef', 'must not be empty');
    }
    final valid = RegExp(r'^[a-z0-9]+$');
    if (!valid.hasMatch(projectRef)) {
      throw ArgumentError.value(
        projectRef,
        'projectRef',
        'must be lowercase alphanumeric (e.g. "vshgjqqosbcoshzyznfq"); '
            'do not include the protocol, host, or trailing path',
      );
    }
  }
}
