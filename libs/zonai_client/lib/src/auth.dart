import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/src/admin_auth.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/types/jwt.dart';

class Auth {
  Auth({required AuthDataSource auth, required Storage storage})
    : _auth = auth,
      _storage = storage,
      admin = AdminAuth(auth: auth);

  final AuthDataSource _auth;
  final Storage _storage;
  final AdminAuth admin;

  String? _token;
  Future<String?> get token async {
    if (_token case final value?) {
      return value;
    }

    if (await _storage['token'] case final String token) {
      return token;
    }

    return null;
  }

  Future<void> setToken(String? value) async {
    _token = value;
    if (value == null) {
      _storage.remove('token');
    } else {
      _storage.save('token', value);
    }
  }

  Future<Jwt?> get jwt async {
    final token = _token ?? await _storage['token'];
    if (token is! String) {
      return null;
    }

    return Jwt.parse(token);
  }

  Future<void> setJwt(Jwt value) async {
    await _storage.save('token', value.toJson());
  }

  Future<void> clearJwt() async {
    await _storage.remove('token');
  }

  Future<AuthSession?> authenticate({
    required AuthBody body,
    String? authorization,
  }) async {
    final raw = await _auth.authenticate(
      body: body,
      authorization: authorization,
    );
    return raw == null ? null : AuthSession.fromJson(raw);
  }

  /// Sign in with email and password.
  Future<AuthSession?> signIn({
    required SignInAuthBody body,
    String? authorization,
  }) async {
    final raw = await _auth.authenticate(
      body: body,
      authorization: authorization,
    );
    return raw == null ? null : AuthSession.fromJson(raw);
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
    return raw == null ? null : AuthSession.fromJson(raw);
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
    return raw == null ? null : AuthSession.fromJson(raw);
  }

  Future<AuthSession?> refreshToken({String? authorization}) async {
    final raw = await _auth.refreshToken(authorization: authorization ?? '');
    return raw == null ? null : AuthSession.fromJson(raw);
  }

  Future<void> logout({String? authorization}) async {
    await _auth.logout(authorization: authorization ?? '');
  }

  Future<void> logoutAll({String? authorization}) async {
    await _auth.logoutAll(authorization: authorization ?? '');
  }
}
