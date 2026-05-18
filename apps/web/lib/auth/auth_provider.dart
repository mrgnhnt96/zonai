import 'package:jaspr_riverpod/jaspr_riverpod.dart';

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);

class AuthNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void signIn() {
    if (!state) state = true;
  }

  void signOut() {
    if (state) state = false;
  }
}
