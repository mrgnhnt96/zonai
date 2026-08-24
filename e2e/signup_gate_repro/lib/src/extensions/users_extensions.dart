import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_signup_gate_repro/src/schemas/users.dart';

UsersExtensions main() => UsersExtensions();

/// An app that only lets some addresses register.
///
/// Split by domain rather than by a flag the test flips, so both outcomes are
/// exercised in the *same* compiled worker within one run: a fixture that can
/// only decline proves the refusal but not that anyone can still sign up, and
/// a build step between the two cases would be a different binary answering
/// each question.
final class UsersExtensions extends Extension<User> with AuthExtension<User> {
  UsersExtensions() : super(users);

  static const declinedDomain = '@blocked.test';
  static const reason = 'Sign-up from that domain is not accepted';

  @override
  Future<void> beforeSignUp(SignUpCandidate candidate, Jwt? jwt) async {
    if (candidate.email.endsWith(declinedDomain)) {
      throw const SignUpDeclinedException(reason);
    }
  }

  /// Silences the default, which sends a verify-email to any `HasEmail`
  /// collection — and `PasswordAuth implements HasEmail`, so this table is
  /// one.
  ///
  /// Not tidiness. The fixture has no SMTP server, so that send is still in
  /// flight when the test disposes its `ZonaiDb`, and `Mailman.dispose` kills
  /// the worker with `failPending: true` rather than draining it. The
  /// *allowed* sign-up then fails with `OPERATIONS worker failed / Process
  /// killed` while the declined one passes — because a declined sign-up never
  /// reaches `onSignUp` at all. That reads exactly like "the gate broke the
  /// happy path", and it cost a diagnosis to find it was the email.
  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {}
}
