import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/src/admin_auth.dart';
import 'package:zonai_schema/zonai_schema.dart';

class Auth {
  Auth({required this._auth}) : admin = AdminAuth(auth: _auth);

  final AuthDataSource _auth;
  final AdminAuth admin;

  Future<Map<String, Object?>?> authenticate({required AuthBody body}) async {
    return await _auth.authenticate(body: body);
  }

  /// Sign in with email and password.
  Future<Map<String, Object?>?> signIn({required SignInAuthBody body}) async {
    return await _auth.authenticate(body: body);
  }

  /// Sign up with email and password.
  Future<Map<String, Object?>?> signUp({required SignUpAuthBody body}) async {
    return await _auth.authenticate(body: body);
  }

  Future<void> sentOtp({required SendOtpAuthBody body}) async {
    await _auth.authenticate(body: body);
  }

  Future<void> sendMagicLink({required SendMagicLinkAuthBody body}) async {
    await _auth.authenticate(body: body);
  }

  Future<void> sendResetPassword({required ResetPasswordAuthBody body}) async {
    await _auth.sendResetPassword(body: body);
  }

  Future<Map<String, Object?>?> confirm({required VerifyAuthBody body}) async {
    return await _auth.confirm(body: body);
  }

  Future<Map<String, Object?>?> refreshToken() async {
    return await _auth.refreshToken(authorization: '');
  }

  Future<void> logout() async {
    await _auth.logout(authorization: '');
  }

  Future<void> logoutAll() async {
    await _auth.logoutAll(authorization: '');
  }
}
