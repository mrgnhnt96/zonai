import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);

class AuthNotifier extends Notifier<bool> {
  AuthNotifier({this.initialSignedIn = false});

  /// Seed from the incoming request cookie during SSR (see [AppShell] override).
  final bool initialSignedIn;

  @override
  bool build() {
    final binding = ref.binding;
    if (!binding.isClient) {
      return initialSignedIn;
    }
    return _hasAuthToken();
  }

  Future<void> signInWithPassword({required String email, required String password}) async {
    try {
      final session = await revaliServer.auth.adminSignIn(
        body: AdminSignInAuthBody(email: email, password: password),
      );

      final accessToken = session['accessToken'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw StateError('Sign-in succeeded but no access token was returned');
      }

      signIn(accessToken);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  void signIn(String accessToken) {
    ZonaiCookie.authToken.write(accessToken);
    state = true;
  }

  Future<void> signOut() async {
    final token = ZonaiCookie.authToken.read();
    if (token != null) {
      try {
        await revaliServer.auth.logout(authorization: 'Bearer $token');
      } catch (_) {}
    }
    ZonaiCookie.authToken.remove();
    state = false;
  }

  static bool _hasAuthToken() {
    final token = ZonaiCookie.authToken.read();
    return token != null && token.isNotEmpty;
  }
}
