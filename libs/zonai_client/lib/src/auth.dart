import 'package:revali_client/revali_client.dart' show ServerException;
import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/src/admin_auth.dart';
import 'package:zonai_client/src/password_reset_required_exception.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/types/jwt.dart';

class Auth {
  Auth({required AuthDataSource auth, required Storage storage})
    : _auth = auth,
      _storage = storage,
      admin = AdminAuth(auth: auth, storage: storage);

  final AuthDataSource _auth;
  final Storage _storage;
  final AdminAuth admin;

  String? _token;

  /// The stored bearer token (`accessToken` compact JWT string).
  Future<String?> get token async {
    if (_token case final value?) {
      return value;
    }

    if (await _storage[AuthSession.key] case final String token) {
      return token;
    }

    return null;
  }

  /// Persists the bearer token returned as [AuthSession.accessToken].
  Future<void> setToken(String? value) async {
    _token = value;
    if (value == null) {
      await _storage.remove(AuthSession.key);
    } else {
      await _storage.save(AuthSession.key, value);
    }
  }

  /// Parsed claims for the stored bearer token.
  Future<Jwt?> get jwt async {
    if (await token case final String token) {
      return Jwt.parse(token);
    }
    return null;
  }

  /// Clears the stored bearer token.
  Future<void> clearToken() async {
    await setToken(null);
  }

  Future<AuthSession?> _sessionFromRaw(Map<String, Object?>? raw) async {
    if (raw == null) {
      return null;
    }
    final session = AuthSession.fromJson(raw);
    await setToken(session.accessToken);
    return session;
  }

  Future<AuthSession?> authenticate({
    required AuthBody body,
    String? authorization,
  }) async {
    final raw = await translatePasswordResetRefusal(
      () => _auth.authenticate(body: body, authorization: authorization),
    );
    return _sessionFromRaw(raw);
  }

  /// Sign in with email and password.
  Future<AuthSession?> signIn({
    required SignInAuthBody body,
    String? authorization,
  }) async {
    // Prefer the dedicated /auth/sign-in route (typed SignInAuthBody) over the
    // polymorphic /auth authenticate endpoint — avoids 500s when a caller
    // omits `type`/`table` and keeps sign-in on the BodyRateLimit(.signIn) bucket.
    final raw = await translatePasswordResetRefusal(
      () => _auth.signIn(body: body),
    );
    return _sessionFromRaw(raw);
  }

  /// Finish a forced password reset and end up signed in.
  ///
  /// Two calls, not one, and that is the server's contract rather than an
  /// oversight: `POST /auth/confirm` returns NO session for a password reset,
  /// because the emailed variant is completed by whoever holds the link and
  /// handing that party a session would be a very different feature. Rather
  /// than change the contract for the forced path only, the client signs in
  /// again with the password the caller just chose.
  ///
  /// ```dart
  /// try {
  ///   await client.auth.signIn(body: body);
  /// } on PasswordResetRequiredException catch (e) {
  ///   await client.auth.completePasswordReset(
  ///     refusal: e,
  ///     email: body.email,
  ///     newPassword: chosen,
  ///     table: body.table,
  ///   );
  /// }
  /// ```
  ///
  /// Throws whatever the confirm rejected with, unchanged — notably a
  /// `ServerException` with status 422 when [newPassword] is the password the
  /// account already has. That one does NOT consume the ticket, so the same
  /// [refusal] can be passed again with a different password.
  Future<AuthSession?> completePasswordReset({
    required PasswordResetRequiredException refusal,
    required String email,
    required String newPassword,
    String table = 'users',
  }) async {
    await confirm(
      body: VerifyAuthBody.confirmResetPassword(
        token: refusal.resetToken,
        newPassword: newPassword,
      ),
    );

    return signIn(
      body: SignInAuthBody(table: table, email: email, password: newPassword),
    );
  }

  /// Sign up with email and password.
  Future<AuthSession?> signUp({
    required SignUpAuthBody body,
    String? authorization,
  }) async {
    final raw = await _auth.authenticate(
      body: body,
      authorization: authorization,
    );
    return _sessionFromRaw(raw);
  }

  Future<void> sentOtp({
    required SendOtpAuthBody body,
    String? authorization,
  }) async {
    await _auth.authenticate(body: body, authorization: authorization);
  }

  Future<void> sendMagicLink({
    required SendMagicLinkAuthBody body,
    String? authorization,
  }) async {
    await _auth.authenticate(body: body, authorization: authorization);
  }

  Future<void> sendResetPassword({
    required ResetPasswordAuthBody body,
    String? authorization,
  }) async {
    await _auth.sendResetPassword(body: body, authorization: authorization);
  }

  Future<void> sendVerifyEmail({
    VerifyEmailAuthBody? body,
    String? authorization,
  }) async {
    await _auth.sendVerifyEmail(body: body, authorization: authorization ?? '');
  }

  Future<AuthSession?> confirm({required VerifyAuthBody body}) async {
    final raw = await _auth.confirm(body: body);
    return _sessionFromRaw(raw);
  }

  Future<AuthSession?> refreshToken({String? authorization}) async {
    final raw = await _auth.refreshToken(authorization: authorization ?? '');
    return _sessionFromRaw(raw);
  }

  /// The public, redacted OAuth providers configured on the server
  /// (`docs/oauth-design.md` §2.4). Pass [table] to narrow to one auth
  /// collection; omit it to list every OAuth-enabled table at once.
  Future<List<OAuthProviderPublic>> providers({String? table}) async {
    final raw = await _auth.oauthProviders(table: table);
    return raw.map(OAuthProviderPublic.fromJson).toList();
  }

  /// The URL to open in a browser / custom tab to start [provider]'s
  /// server-driven redirect flow (design §3.1). Built from the base URL the
  /// generated [Server] recorded at construction, not fetched: `GET
  /// oauth/start/:provider` always redirects, so there is no response body
  /// for a client to read a URL from.
  Future<Uri> startUrl({
    required String table,
    required String provider,
    String? redirectTo,
  }) async {
    final baseUrl = await _storage['__BASE_URL__'];
    if (baseUrl is! String || baseUrl.isEmpty) {
      throw StateError('Base URL not set');
    }
    return Uri.parse(baseUrl).replace(
      path: '/auth/oauth/start/$provider',
      queryParameters: {
        'table': table,
        if (redirectTo != null) 'redirect_to': redirectTo,
      },
    );
  }

  /// §3.2: exchange a PKCE `code` the app obtained itself (e.g. by driving
  /// [startUrl] through its own in-app browser with a matching
  /// `redirectUri`) for a session.
  Future<AuthSession?> complete({
    required String table,
    required String provider,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final raw = await _auth.oauth(
      body: OAuthBody.code(
        table: table,
        provider: provider,
        code: code,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
      ),
    );
    return _sessionFromRaw(raw);
  }

  /// §3.2, the primary path for a Flutter app that already ran the
  /// provider's own SDK (`google_sign_in`, Sign in with Apple) and holds a
  /// provider `idToken`.
  Future<AuthSession?> signInWithIdToken({
    required String table,
    required String provider,
    required String idToken,
  }) async {
    final raw = await _auth.oauth(
      body: OAuthBody.idToken(
        table: table,
        provider: provider,
        idToken: idToken,
      ),
    );
    return _sessionFromRaw(raw);
  }

  Future<void> logout({String? authorization}) async {
    await _auth.logout(authorization: authorization ?? '');
  }

  Future<void> logoutAll({String? authorization}) async {
    await _auth.logoutAll(authorization: authorization ?? '');
  }
}

/// Re-throws a [ServerException] as a [PasswordResetRequiredException] when it
/// is one.
///
/// Shared by [Auth] and [AdminAuth] because all three password doors —
/// `/auth/sign-in`, `/auth` with `type: signIn`, and `/auth/admin` — land on
/// the same server-side gate, so a client that translated only one of them
/// would leave the dashboard's own sign-in holding a raw envelope.
///
/// Anything that is not this failure is re-thrown UNCHANGED, including a 403
/// carrying some other `code`. Reshaping another failure into this type would
/// send a caller off to collect a new password for a problem that is not
/// about passwords.
Future<T> translatePasswordResetRefusal<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on ServerException catch (e) {
    throw PasswordResetRequiredException.tryFrom(e) ?? e;
  }
}
