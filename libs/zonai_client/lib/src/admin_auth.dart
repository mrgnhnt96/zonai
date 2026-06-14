import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/payloads.dart';

class AdminAuth {
  const AdminAuth({required this._auth});

  final AuthDataSource _auth;

  Future<AuthSession?> signIn({
    required AdminSignInAuthBody body,
    String? authorization,
  }) async {
    final raw = await _auth.authenticate(
      body: body,
      authorization: authorization,
    );
    return raw == null ? null : AuthSession.fromJson(raw);
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
}
