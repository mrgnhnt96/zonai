/// Wire formats for the OAuth HTTP surface (`docs/oauth-design.md` §3).
///
/// Deliberately a family of its own rather than new members of the sealed
/// `AuthBody` hierarchy in `auth_password_body.dart`. `AuthBody` is `sealed`,
/// so a subtype has to live in that same file, and every exhaustive
/// `switch (AuthBody)` in the repo -- `AuthHandler.authenticate`'s payload
/// mapping among them -- would gain a branch describing a flow that does not
/// go through `zonaiDB.authenticate(table, AuthBody)` at all. The OAuth
/// routes call `startOAuth` / `completeOAuth` / `authenticate` with their own
/// payload types instead, so the bodies stay their own family.
library;

/// Body of `POST /auth/oauth` -- the native / public-client flow
/// (design §3.2). The app has already run the provider's own SDK and hands
/// zonai the result.
///
/// Two shapes, and exactly one of them per request:
/// - [OAuthIdTokenBody]: `{table, provider, idToken}` for OIDC providers
/// - [OAuthCodeBody]: `{table, provider, code, codeVerifier, redirectUri}`
///   for the PKCE pair the app itself generated
///
/// Neither carries a client secret: a public client does not have one, which
/// is the whole reason this flow exists separately from §3.1's redirect.
sealed class OAuthBody {
  const OAuthBody({
    required this.table,
    required this.provider,
    required this.type,
  });

  factory OAuthBody.fromJson(Map<String, dynamic> json) {
    // Tolerant of a missing `type` the same way `AuthBody.fromJson` is: the
    // two shapes are unambiguous from their own fields, and falling through
    // to a null cast would surface as an HTTP 500 rather than a 400.
    final type =
        json['type'] ??
        (json['idToken'] is String
            ? OAuthIdTokenBody._type
            : json['code'] is String
            ? OAuthCodeBody._type
            : null);

    return switch (type) {
      OAuthIdTokenBody._type => OAuthIdTokenBody.fromJson(json),
      OAuthCodeBody._type => OAuthCodeBody.fromJson(json),
      _ => throw ArgumentError(
        'Invalid oauth body type: ${json['type']}. Send either '
        '{table, provider, idToken} or '
        '{table, provider, code, codeVerifier, redirectUri}.',
      ),
    };
  }

  factory OAuthBody.idToken({
    required String table,
    required String provider,
    required String idToken,
  }) = OAuthIdTokenBody;

  factory OAuthBody.code({
    required String table,
    required String provider,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) = OAuthCodeBody;

  /// Auth collection to sign in against.
  final String table;

  /// `OAuthProvider.id`, e.g. `'google'`.
  final String provider;

  final String type;

  Map<String, dynamic> toJson() => {
    'table': table,
    'provider': provider,
    'type': type,
  };

  /// Never includes [OAuthIdTokenBody.idToken] or [OAuthCodeBody.code]:
  /// design §4 item 7 -- a body that lands in an error message or a log line
  /// must not carry the credential it was rejected for. [toJson] is the
  /// serializer; this is what a human reads.
  @override
  String toString() => '$runtimeType(table: $table, provider: $provider)';
}

/// `{table, provider, idToken}` -- the app ran an OIDC provider's SDK and
/// has an `id_token` to be verified server-side (signature, `iss`, `aud`,
/// `exp`). No `nonce` check: the client owns the nonce in this flow, zonai
/// never minted one to compare against.
final class OAuthIdTokenBody extends OAuthBody {
  const OAuthIdTokenBody({
    required super.table,
    required super.provider,
    required this.idToken,
  }) : super(type: _type);

  factory OAuthIdTokenBody.fromJson(Map<String, dynamic> json) {
    final idToken = json['idToken'];
    if (idToken is! String || idToken.isEmpty) {
      throw ArgumentError(
        'OAuthIdTokenBody requires a non-empty string idToken '
        '(got ${idToken.runtimeType})',
      );
    }
    return OAuthIdTokenBody(
      table: _requiredString(json, 'table'),
      provider: _requiredString(json, 'provider'),
      idToken: idToken,
    );
  }

  static const _type = 'oauthIdToken';

  final String idToken;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'idToken': idToken};
}

/// `{table, provider, code, codeVerifier, redirectUri}` -- the app ran the
/// PKCE dance itself and hands zonai the authorization code to exchange.
final class OAuthCodeBody extends OAuthBody {
  const OAuthCodeBody({
    required super.table,
    required super.provider,
    required this.code,
    required this.codeVerifier,
    required this.redirectUri,
  }) : super(type: _type);

  factory OAuthCodeBody.fromJson(Map<String, dynamic> json) {
    return OAuthCodeBody(
      table: _requiredString(json, 'table'),
      provider: _requiredString(json, 'provider'),
      code: _requiredString(json, 'code'),
      codeVerifier: _requiredString(json, 'codeVerifier'),
      redirectUri: _requiredString(json, 'redirectUri'),
    );
  }

  static const _type = 'oauthCode';

  final String code;
  final String codeVerifier;
  final String redirectUri;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'code': code,
    'codeVerifier': codeVerifier,
    'redirectUri': redirectUri,
  };
}

/// Body of `POST /auth/oauth/callback/:provider`.
///
/// Apple is why this type exists. Sign in with Apple posts its callback as
/// `application/x-www-form-urlencoded` with `response_mode=form_post`
/// whenever `name` or `email` scopes were requested -- which is Apple's own
/// default in `OAuthProvider.apple` -- rather than as the `GET` with a query
/// string every other provider sends. Same three fields, different
/// transport, so the callback route accepts both and hands the handler the
/// same values.
///
/// [user] is Apple's first-authorization-only JSON blob carrying the
/// person's name. It is accepted and ignored here: `OAuthClaimMap.name` is
/// unset for Apple precisely because that field never appears again, and
/// nothing downstream reads it yet.
class OAuthCallbackBody {
  const OAuthCallbackBody({
    this.code,
    this.state,
    this.error,
    this.errorDescription,
    this.user,
  });

  factory OAuthCallbackBody.fromJson(Map<String, dynamic> json) {
    return OAuthCallbackBody(
      code: json['code'] as String?,
      state: json['state'] as String?,
      error: json['error'] as String?,
      errorDescription: json['error_description'] as String?,
      user: json['user'] as String?,
    );
  }

  /// The authorization code. Absent when the provider sent [error] instead.
  final String? code;

  /// Opaque handle for the `oauthState` challenge minted at `start`.
  final String? state;

  /// RFC 6749 §4.1.2.1 error code, e.g. `access_denied`.
  final String? error;

  final String? errorDescription;

  /// Apple only, first authorization only: a JSON blob with the user's name.
  final String? user;

  /// Field *names* only. [code] and [state] are exactly the two values
  /// design §4 item 7 forbids from reaching a log line or an error message,
  /// and an un-overridden `toString` on a body that a 4xx path stringifies
  /// is how they would get there.
  @override
  String toString() =>
      'OAuthCallbackBody(code: ${code == null ? 'null' : '<redacted>'}, '
      'state: ${state == null ? 'null' : '<redacted>'}, error: $error)';
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw ArgumentError(
      'Missing or empty required field "$key" (got ${value.runtimeType})',
    );
  }
  return value;
}
