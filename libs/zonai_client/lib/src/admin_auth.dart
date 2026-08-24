import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/src/auth.dart' show translatePasswordResetRefusal;
import 'package:zonai_client/src/password_reset_required_exception.dart';
import 'package:zonai_schema/payloads.dart';

class AdminAuth {
  const AdminAuth({required AuthDataSource auth, required Storage storage})
    : _auth = auth,
      _storage = storage;

  final AuthDataSource _auth;
  final Storage _storage;

  /// Throws [PasswordResetRequiredException] when the admin account owes a new
  /// password. This is the door where that matters most: an admin who is
  /// forced to reset and cannot complete it here has no dashboard.
  Future<AuthSession?> signIn({
    required AdminSignInAuthBody body,
    String? authorization,
  }) async {
    final raw = await translatePasswordResetRefusal(
      () => _auth.authenticate(body: body, authorization: authorization),
    );
    if (raw == null) {
      return null;
    }
    final session = AuthSession.fromJson(raw);
    await _storage.save(AuthSession.key, session.accessToken);
    return session;
  }

  Future<void> sendOtp({
    required AdminSendOtpAuthBody body,
    String? authorization,
  }) async {
    await _auth.authenticate(body: body, authorization: authorization);
  }

  Future<void> sendMagicLink({
    required AdminSendMagicLinkAuthBody body,
    String? authorization,
  }) async {
    await _auth.authenticate(body: body, authorization: authorization);
  }

  /// Finish a forced password reset for an ADMIN and end up signed in.
  ///
  /// Same two-call shape as `Auth.completePasswordReset`, and same reason: a
  /// password-reset confirm returns no session. It signs back in through
  /// [signIn], so the new session lands in storage exactly as an ordinary
  /// admin sign-in does.
  Future<AuthSession?> completePasswordReset({
    required PasswordResetRequiredException refusal,
    required String email,
    required String newPassword,
  }) async {
    await _auth.confirm(
      body: VerifyAuthBody.confirmResetPassword(
        token: refusal.resetToken,
        newPassword: newPassword,
      ),
    );

    return signIn(
      body: AdminSignInAuthBody(email: email, password: newPassword),
    );
  }
}
