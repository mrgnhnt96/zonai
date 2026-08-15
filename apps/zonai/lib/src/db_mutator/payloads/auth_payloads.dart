part of payloads;

sealed class AuthPayload extends Payload implements JwtPayload {
  const AuthPayload({required this.authType, this.jwt});

  final AuthType authType;
  final String? jwt;
}

sealed class VerifyAuthPayload extends Payload implements JwtPayload {
  const VerifyAuthPayload({required this.authType, this.jwt});

  final AuthType authType;
  final String? jwt;
}

class PasswordAuthPayload extends AuthPayload {
  const PasswordAuthPayload({
    required this.email,
    required this.password,
    this.object,
    super.jwt,
  }) : super(authType: .password);

  final String email;
  final String password;
  final Map<String, dynamic>? object;
}

class SignInPasswordAuthPayload extends PasswordAuthPayload {
  const SignInPasswordAuthPayload({
    required super.email,
    required super.password,
  });
}

class SignUpPasswordAuthPayload extends PasswordAuthPayload {
  const SignUpPasswordAuthPayload({
    required super.email,
    required super.password,
    super.object,
    super.jwt,
  });
}

class SendOtpAuthPayload extends AuthPayload {
  const SendOtpAuthPayload({required this.email, this.object, super.jwt})
    : super(authType: .otp);

  final String email;
  final Map<String, dynamic>? object;
}

class SendVerifyEmailAuthPayload {
  const SendVerifyEmailAuthPayload({required this.email, required this.table});

  final String email;
  final String table;
}

class VerifyOtpAuthPayload extends VerifyAuthPayload implements AuthPayload {
  const VerifyOtpAuthPayload({
    required this.email,
    required this.code,
    super.jwt,
  }) : super(authType: .otp);

  final String email;
  final String code;
}

class SendMagicLinkAuthPayload extends AuthPayload {
  const SendMagicLinkAuthPayload({required this.email, this.object, super.jwt})
    : super(authType: .magicLink);

  final String email;
  final Map<String, dynamic>? object;
}

class VerifyMagicLinkAuthPayload extends VerifyAuthPayload
    implements AuthPayload {
  const VerifyMagicLinkAuthPayload({required this.secret, super.jwt})
    : super(authType: .magicLink);

  final String secret;
  String get email =>
      throw UnimplementedError('Email is not available in the secret');
}

class ResetPasswordAuthPayload extends AuthPayload {
  const ResetPasswordAuthPayload({required this.email, super.jwt})
    : super(authType: .password);

  final String email;
}

class ConfirmResetPasswordAuthPayload extends VerifyAuthPayload
    implements AuthPayload {
  const ConfirmResetPasswordAuthPayload({
    required this.token,
    required this.newPassword,
    super.jwt,
  }) : super(authType: .password);

  final String token;
  final String newPassword;
}

class VerifyEmailAuthPayload extends VerifyAuthPayload {
  const VerifyEmailAuthPayload({required this.token, super.jwt})
    : super(authType: .password);

  final String token;
}

/// §3.1 step 1: begin the server-driven redirect flow. Not routed through
/// [ZonaiDb.authenticate] — its result is an authorization URL, not an
/// [AuthPayload]-shaped sign-in — see `ZonaiDb.startOAuth`.
class StartOAuthAuthPayload extends AuthPayload {
  const StartOAuthAuthPayload({
    required this.provider,
    this.redirectTo,
    super.jwt,
  }) : super(authType: .oauth);

  /// [OAuthProvider.id], e.g. `'google'`.
  final String provider;

  /// Where to send the user after the callback completes. Must be a
  /// relative path or the app's own origin — see
  /// `OAuthRedirectNotAllowedException`.
  final String? redirectTo;
}

/// §3.1 step 2: complete the server-driven redirect flow. Table and provider
/// are resolved from the consumed `_auth_challenges` row (`target`/`table`),
/// the same way [VerifyMagicLinkAuthPayload] resolves them from its secret
/// rather than taking them as fields — see `ZonaiDb.completeOAuth`.
class CompleteOAuthAuthPayload extends VerifyAuthPayload
    implements AuthPayload {
  const CompleteOAuthAuthPayload({
    required this.state,
    required this.code,
    super.jwt,
  }) : super(authType: .oauth);

  final String state;
  final String code;
}

/// §3.2: the native/public-client flow. The app already ran the provider's
/// own SDK and hands zonai either [idToken] (OIDC providers) or [code] +
/// [codeVerifier] + [redirectUri] (the PKCE pair the app itself generated
/// and exchanged against). Exactly one of those two shapes must be
/// supplied — see `ZonaiDb._nativeOAuth`.
class NativeOAuthAuthPayload extends AuthPayload {
  const NativeOAuthAuthPayload.idToken({
    required this.provider,
    required String idToken,
    super.jwt,
  }) : idToken = idToken,
       code = null,
       codeVerifier = null,
       redirectUri = null,
       super(authType: .oauth);

  const NativeOAuthAuthPayload.code({
    required this.provider,
    required String code,
    required String codeVerifier,
    required String redirectUri,
    super.jwt,
  }) : code = code,
       codeVerifier = codeVerifier,
       redirectUri = redirectUri,
       idToken = null,
       super(authType: .oauth);

  /// [OAuthProvider.id], e.g. `'google'`.
  final String provider;

  final String? idToken;
  final String? code;
  final String? codeVerifier;
  final String? redirectUri;
}
