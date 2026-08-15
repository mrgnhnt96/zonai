import 'package:zonai_schema/src/types/oauth/oauth_brand.dart';
import 'package:zonai_schema/src/types/oauth/oauth_claim_map.dart';
import 'package:zonai_schema/src/types/oauth/oauth_endpoints.dart';
import 'package:zonai_schema/src/types/oauth/oauth_icon.dart';
import 'package:zonai_schema/src/types/oauth/oauth_linking.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider_kind.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider_public.dart';

/// One provider a table's [OAuth] mixin can sign in with.
///
/// Two shapes: [BuiltInOAuthProvider], produced only by the named factories
/// below (`OAuthProvider.google(...)`, etc.), and [CustomOAuthProvider]
/// (`OAuthProvider.custom(...)`), which can express any OAuth2/OIDC provider
/// without a code change here. Both are `sealed`-restricted to this file,
/// mirroring [ExternalIdpConfig]'s split.
sealed class OAuthProvider {
  const OAuthProvider();

  /// Route segment and identity key, e.g. `'google'`. Must be unique within
  /// one table's [OAuth.oauthProviders].
  String get id;

  String get displayName;

  OAuthBrand get brand;

  OAuthEndpoints get endpoints;

  List<String> get scopes;

  OAuthClaimMap get claims;

  bool get usesPkce;

  OAuthLinking get linking;

  /// The redacted view served to the dashboard and Dart client — never
  /// includes [BuiltInOAuthProvider.clientSecret], Apple's private key, or
  /// any endpoint URL.
  OAuthProviderPublic toPublic({required String table}) {
    final self = this;
    return OAuthProviderPublic(
      id: id,
      displayName: displayName,
      table: table,
      kind: switch (self) {
        BuiltInOAuthProvider() => self.kind,
        CustomOAuthProvider() => OAuthProviderKind.custom,
      },
      iconUrl: switch (brand.icon) {
        OAuthIconUrl(:final url) => url,
        _ => null,
      },
      iconSvg: switch (brand.icon) {
        OAuthIconSvg(:final svg) => svg,
        _ => null,
      },
      background: brand.background,
      foreground: brand.foreground,
      startPath: '/auth/oauth/start/$id?table=$table',
    );
  }

  // ---------------------------------------------------------------------
  // Built-in factories. Pure: no network, no runtime dependency, nothing
  // beyond what each provider publishes today. Endpoint/scope/claim
  // sources are cited per factory; re-verify against the provider's docs
  // before trusting an old value, the same as any other pinned external
  // fact.
  // ---------------------------------------------------------------------

  /// Google OAuth 2.0 / OpenID Connect.
  ///
  /// Source: Google's OIDC discovery document,
  /// https://accounts.google.com/.well-known/openid-configuration.
  static BuiltInOAuthProvider google({
    required String clientId,
    required String clientSecret,
    List<String> scopes = const ['openid', 'email', 'profile'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.google');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.google');
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.google,
      id: 'google',
      displayName: 'Google',
      brand: const OAuthBrand(background: '#FFFFFF', foreground: '#1F1F1F'),
      endpoints: const OAuthEndpoints(
        authorization: 'https://accounts.google.com/o/oauth2/v2/auth',
        token: 'https://oauth2.googleapis.com/token',
        userInfo: 'https://openidconnect.googleapis.com/v1/userinfo',
        issuer: 'https://accounts.google.com',
        jwks: 'https://www.googleapis.com/oauth2/v3/certs',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
        picture: 'picture',
      ),
      usesPkce: true,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }

  /// Sign in with Apple.
  ///
  /// Apple has no static `client_secret` — [teamId]/[keyId]/[privateKey]
  /// sign a fresh ES256 JWT per token request (`iss: teamId`, `kid: keyId`,
  /// `sub: clientId`, `aud: https://appleid.apple.com`, max 6-month expiry).
  /// That signer is runtime work, out of scope for this pure factory.
  ///
  /// Apple returns the user's name only on the first authorization, as a
  /// form-post `user` field — never in the `id_token` or on any later
  /// sign-in, which is why [OAuthClaimMap.name] is left unset here.
  ///
  /// Source: Apple's OIDC discovery document,
  /// https://appleid.apple.com/.well-known/openid-configuration, and
  /// Apple's Sign in with Apple REST API docs for the scopes and the
  /// client-secret JWT shape.
  static BuiltInOAuthProvider apple({
    required String clientId,
    required String teamId,
    required String keyId,
    required String privateKey,
    List<String> scopes = const ['name', 'email'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.apple');
    _requireNonEmpty(teamId, 'teamId', 'OAuthProvider.apple');
    _requireNonEmpty(keyId, 'keyId', 'OAuthProvider.apple');
    _requireNonEmpty(privateKey, 'privateKey', 'OAuthProvider.apple');
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.apple,
      id: 'apple',
      displayName: 'Apple',
      brand: const OAuthBrand(background: '#000000', foreground: '#FFFFFF'),
      endpoints: const OAuthEndpoints(
        authorization: 'https://appleid.apple.com/auth/authorize',
        token: 'https://appleid.apple.com/auth/token',
        issuer: 'https://appleid.apple.com',
        jwks: 'https://appleid.apple.com/auth/keys',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
      ),
      usesPkce: false,
      clientId: clientId,
      teamId: teamId,
      keyId: keyId,
      privateKey: privateKey,
      linking: linking,
    );
  }

  /// GitHub OAuth Apps.
  ///
  /// Not OIDC — no `id_token`, no JWKS. `GET /user` can return
  /// `email: null` for accounts with a private primary email; the
  /// verified fallback via `GET /user/emails` is runtime work (out of
  /// scope for this pure factory), which is why
  /// [OAuthClaimMap.emailVerified] is left unset here.
  ///
  /// Source: GitHub's OAuth Apps docs — "Authorizing OAuth apps"
  /// (https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)
  /// for the endpoints, "Scopes for OAuth apps"
  /// (https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps)
  /// for the scope names, and the `GET /user` REST reference for the
  /// claim fields.
  static BuiltInOAuthProvider github({
    required String clientId,
    required String clientSecret,
    List<String> scopes = const ['read:user', 'user:email'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.github');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.github');
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.github,
      id: 'github',
      displayName: 'GitHub',
      brand: const OAuthBrand(background: '#24292F', foreground: '#FFFFFF'),
      endpoints: const OAuthEndpoints(
        authorization: 'https://github.com/login/oauth/authorize',
        token: 'https://github.com/login/oauth/access_token',
        userInfo: 'https://api.github.com/user',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(
        subject: 'id',
        email: 'email',
        name: 'name',
        picture: 'avatar_url',
      ),
      usesPkce: true,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }

  /// Microsoft identity platform (Entra ID), v2.0 endpoint.
  ///
  /// [tenant] defaults to `'common'` (personal + work/school accounts).
  /// The `/common/` endpoint's discovery document publishes a templated
  /// `issuer` (`https://login.microsoftonline.com/{tenantid}/v2.0`) rather
  /// than a concrete one, since the actual issuer depends on which tenant
  /// the signed-in account belongs to — resolving that per sign-in is
  /// runtime work, so [OAuthEndpoints.issuer] is left unset unless a
  /// specific [tenant] is supplied.
  ///
  /// Source: Microsoft's OIDC discovery document for the common endpoint,
  /// https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration.
  static BuiltInOAuthProvider microsoft({
    required String clientId,
    required String clientSecret,
    String tenant = 'common',
    List<String> scopes = const ['openid', 'email', 'profile'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.microsoft');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.microsoft');
    _requireNonEmpty(tenant, 'tenant', 'OAuthProvider.microsoft');
    final isMultiTenant = const {
      'common',
      'organizations',
      'consumers',
    }.contains(tenant);
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.microsoft,
      id: 'microsoft',
      displayName: 'Microsoft',
      brand: const OAuthBrand(background: '#2F2F2F', foreground: '#FFFFFF'),
      endpoints: OAuthEndpoints(
        authorization:
            'https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize',
        token: 'https://login.microsoftonline.com/$tenant/oauth2/v2.0/token',
        userInfo: 'https://graph.microsoft.com/oidc/userinfo',
        issuer: isMultiTenant
            ? null
            : 'https://login.microsoftonline.com/$tenant/v2.0',
        jwks:
            'https://login.microsoftonline.com/$tenant/discovery/v2.0/keys',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(subject: 'sub', email: 'email', name: 'name'),
      usesPkce: true,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }

  /// Facebook Login.
  ///
  /// Not verifiable via `id_token` in the standard web login flow — no
  /// `issuer`/`jwks` here, identity comes from the Graph API `/me` call
  /// instead. [OAuthClaimMap.picture] is a dotted path because `/me`
  /// nests it (`{"picture": {"data": {"url": "..."}}}`).
  ///
  /// Source: Meta's "Manually Build a Login Flow" guide
  /// (https://developers.facebook.com/docs/facebook-login/guides/advanced/manual-flow/)
  /// and "Get a User Access Token"
  /// (https://developers.facebook.com/docs/facebook-login/guides/access-tokens/get-a-user-access-token),
  /// current Graph API version v25.0 at time of writing — re-pin the
  /// version when it's deprecated.
  static BuiltInOAuthProvider facebook({
    required String clientId,
    required String clientSecret,
    List<String> scopes = const ['email', 'public_profile'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.facebook');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.facebook');
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.facebook,
      id: 'facebook',
      displayName: 'Facebook',
      brand: const OAuthBrand(background: '#1877F2', foreground: '#FFFFFF'),
      endpoints: const OAuthEndpoints(
        authorization: 'https://www.facebook.com/v25.0/dialog/oauth',
        token: 'https://graph.facebook.com/v25.0/oauth/access_token',
        userInfo: 'https://graph.facebook.com/v25.0/me',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(
        subject: 'id',
        email: 'email',
        name: 'name',
        picture: 'picture.data.url',
      ),
      usesPkce: false,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }

  /// Discord OAuth2.
  ///
  /// Not OIDC — no `id_token`, no JWKS. [OAuthClaimMap.picture] is left
  /// unset because Discord's avatar is a URL assembled from the user id,
  /// avatar hash and an extension chosen by format (`.png`/`.gif`), not a
  /// single claim path — that assembly is runtime work.
  ///
  /// Source: Discord's OAuth2 docs,
  /// https://docs.discord.com/developers/topics/oauth2, and the "Users"
  /// resource reference for the claim field names.
  static BuiltInOAuthProvider discord({
    required String clientId,
    required String clientSecret,
    List<String> scopes = const ['identify', 'email'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.discord');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.discord');
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.discord,
      id: 'discord',
      displayName: 'Discord',
      brand: const OAuthBrand(background: '#5865F2', foreground: '#FFFFFF'),
      endpoints: const OAuthEndpoints(
        authorization: 'https://discord.com/oauth2/authorize',
        token: 'https://discord.com/api/oauth2/token',
        userInfo: 'https://discord.com/api/users/@me',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(
        subject: 'id',
        email: 'email',
        emailVerified: 'verified',
        name: 'username',
      ),
      usesPkce: true,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }

  /// GitLab OmniAuth / OIDC (gitlab.com; pass a self-managed instance's own
  /// endpoints via [OAuthProvider.custom] instead).
  ///
  /// Source: GitLab's OIDC discovery document,
  /// https://gitlab.com/.well-known/openid-configuration.
  static BuiltInOAuthProvider gitlab({
    required String clientId,
    required String clientSecret,
    List<String> scopes = const ['openid', 'email', 'profile'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.gitlab');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.gitlab');
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.gitlab,
      id: 'gitlab',
      displayName: 'GitLab',
      brand: const OAuthBrand(background: '#FC6D26', foreground: '#FFFFFF'),
      endpoints: const OAuthEndpoints(
        authorization: 'https://gitlab.com/oauth/authorize',
        token: 'https://gitlab.com/oauth/token',
        userInfo: 'https://gitlab.com/oauth/userinfo',
        issuer: 'https://gitlab.com',
        jwks: 'https://gitlab.com/oauth/discovery/keys',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
        picture: 'picture',
      ),
      usesPkce: true,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }

  /// "Sign In with LinkedIn using OpenID Connect".
  ///
  /// Source: LinkedIn's OIDC discovery document,
  /// https://www.linkedin.com/oauth/.well-known/openid-configuration.
  static BuiltInOAuthProvider linkedin({
    required String clientId,
    required String clientSecret,
    List<String> scopes = const ['openid', 'profile', 'email'],
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.linkedin');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.linkedin');
    return BuiltInOAuthProvider._(
      kind: OAuthProviderKind.linkedin,
      id: 'linkedin',
      displayName: 'LinkedIn',
      brand: const OAuthBrand(background: '#0A66C2', foreground: '#FFFFFF'),
      endpoints: const OAuthEndpoints(
        authorization: 'https://www.linkedin.com/oauth/v2/authorization',
        token: 'https://www.linkedin.com/oauth/v2/accessToken',
        userInfo: 'https://api.linkedin.com/v2/userinfo',
        issuer: 'https://www.linkedin.com/oauth',
        jwks: 'https://www.linkedin.com/oauth/openid/jwks',
      ),
      scopes: scopes,
      claims: const OAuthClaimMap(
        subject: 'sub',
        email: 'email',
        emailVerified: 'email_verified',
        name: 'name',
        picture: 'picture',
      ),
      usesPkce: true,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }

  /// Any other OAuth2/OIDC provider. Every field is explicit — this is the
  /// escape hatch for a provider zonai has no named factory for.
  static CustomOAuthProvider custom({
    required String id,
    required String displayName,
    required OAuthEndpoints endpoints,
    required List<String> scopes,
    required OAuthClaimMap claims,
    required String clientId,
    required String clientSecret,
    OAuthBrand brand = const OAuthBrand(),
    bool usesPkce = true,
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) {
    _requireNonEmpty(id, 'id', 'OAuthProvider.custom');
    _requireNonEmpty(displayName, 'displayName', 'OAuthProvider.custom');
    _requireNonEmpty(clientId, 'clientId', 'OAuthProvider.custom');
    _requireNonEmpty(clientSecret, 'clientSecret', 'OAuthProvider.custom');
    return CustomOAuthProvider._(
      id: id,
      displayName: displayName,
      brand: brand,
      endpoints: endpoints,
      scopes: scopes,
      claims: claims,
      usesPkce: usesPkce,
      clientId: clientId,
      clientSecret: clientSecret,
      linking: linking,
    );
  }
}

void _requireNonEmpty(String value, String field, String context) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(
      value,
      field,
      '$context: $field must not be empty',
    );
  }
}

/// A provider built by one of [OAuthProvider]'s named factories
/// (`.google(...)`, `.github(...)`, etc.) — never constructed directly.
/// Endpoints, scopes, claim map and brand are baked in; only credentials
/// (and, for the standard providers, `scopes`/`linking`) are caller-supplied.
final class BuiltInOAuthProvider extends OAuthProvider {
  const BuiltInOAuthProvider._({
    required this.kind,
    required String id,
    required String displayName,
    required OAuthBrand brand,
    required OAuthEndpoints endpoints,
    required List<String> scopes,
    required OAuthClaimMap claims,
    required bool usesPkce,
    required this.clientId,
    this.clientSecret,
    this.teamId,
    this.keyId,
    this.privateKey,
    OAuthLinking linking = OAuthLinking.byVerifiedEmail,
  }) : _id = id,
       _displayName = displayName,
       _brand = brand,
       _endpoints = endpoints,
       _scopes = scopes,
       _claims = claims,
       _usesPkce = usesPkce,
       _linking = linking;

  final OAuthProviderKind kind;

  final String _id;
  final String _displayName;
  final OAuthBrand _brand;
  final OAuthEndpoints _endpoints;
  final List<String> _scopes;
  final OAuthClaimMap _claims;
  final bool _usesPkce;
  final OAuthLinking _linking;

  /// OAuth2 `client_id`. Non-empty for every built-in provider.
  final String clientId;

  /// OAuth2 `client_secret`. Every built-in except Apple, which signs a
  /// fresh ES256 JWT per token request from [teamId]/[keyId]/[privateKey]
  /// instead of holding a static secret.
  final String? clientSecret;

  /// Apple Developer team identifier (`iss` of the client-secret JWT).
  final String? teamId;

  /// Apple Sign in with Apple key identifier (`kid` of the client-secret
  /// JWT).
  final String? keyId;

  /// PEM-encoded `.p8` private key used to sign Apple's client-secret JWT.
  final String? privateKey;

  @override
  String get id => _id;
  @override
  String get displayName => _displayName;
  @override
  OAuthBrand get brand => _brand;
  @override
  OAuthEndpoints get endpoints => _endpoints;
  @override
  List<String> get scopes => _scopes;
  @override
  OAuthClaimMap get claims => _claims;
  @override
  bool get usesPkce => _usesPkce;
  @override
  OAuthLinking get linking => _linking;
}

/// A hand-described OAuth2/OIDC provider, built by
/// [OAuthProvider.custom] — never constructed directly. Every field is
/// explicit, so this can express any provider without a code change to
/// `zonai_schema`.
final class CustomOAuthProvider extends OAuthProvider {
  const CustomOAuthProvider._({
    required this.id,
    required this.displayName,
    required this.brand,
    required this.endpoints,
    required this.scopes,
    required this.claims,
    required this.clientId,
    required this.clientSecret,
    this.usesPkce = true,
    this.linking = OAuthLinking.byVerifiedEmail,
  });

  @override
  final String id;
  @override
  final String displayName;
  @override
  final OAuthBrand brand;
  @override
  final OAuthEndpoints endpoints;
  @override
  final List<String> scopes;
  @override
  final OAuthClaimMap claims;
  @override
  final bool usesPkce;
  @override
  final OAuthLinking linking;

  final String clientId;
  final String clientSecret;
}
