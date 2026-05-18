import 'package:jaspr_riverpod/jaspr_riverpod.dart';
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
    return ZonaiCookie.signedIn.readFlag();
  }

  void signIn() {
    ZonaiCookie.signedIn.writeFlag(true);
    state = true;
  }

  void signOut() {
    ZonaiCookie.signedIn.writeFlag(false);
    state = false;
  }
}
