import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/zonai_schema.dart';

class AdminAuth {
  const AdminAuth({required this._auth});

  final AuthDataSource _auth;

  Future<Map<String, Object?>?> signIn({
    required AdminSignInAuthBody body,
    String? authorization,
  }) async {
    return await _auth.authenticate(body: body, authorization: authorization);
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
