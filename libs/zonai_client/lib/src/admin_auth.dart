import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/payloads.dart';

class AdminAuth {
  const AdminAuth({required AuthDataSource auth, required Storage storage})
    : _auth = auth,
      _storage = storage;

  final AuthDataSource _auth;
  final Storage _storage;

  Future<AuthSession?> signIn({
    required AdminSignInAuthBody body,
    String? authorization,
  }) async {
    final raw = await _auth.authenticate(
      body: body,
      authorization: authorization,
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
}
