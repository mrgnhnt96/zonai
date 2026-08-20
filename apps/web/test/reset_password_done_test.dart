import 'package:jaspr/dom.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_web/components/reset_password_confirm_screen.dart';

/// What a finished password reset shows, and — the point of this file — what it
/// does not.
///
/// The reset page is served by the dashboard, but the link that reaches it is
/// emailed to whoever owns the account, on any auth table. Most people who open
/// one are an app's own users, and the only sign-in this app can offer is the
/// dashboard's. A "Sign in" button here was therefore pointing an app's users
/// at somebody else's admin panel, so the success state is now terminal.
///
/// Pumped directly rather than driven through the form: `_success` sits behind
/// an async call to `confirmResetPassword`, and a test that had to fake the
/// client to reach it would be pinning the mock, not the markup.
void main() {
  group('ResetPasswordDoneCard', () {
    testComponents('confirms the password was reset', (tester) async {
      tester.pumpComponent(const ResetPasswordDoneCard());
      await tester.pump();

      expect(find.text('Password updated'), findsOneComponent);
      expect(find.text('Your password has been reset. You can now sign in with your new password.'), findsOneComponent);
    });

    testComponents('offers no route into the dashboard', (tester) async {
      tester.pumpComponent(const ResetPasswordDoneCard());
      await tester.pump();

      // Both shapes, because the affordance being removed could come back as
      // either: a button that navigates, or a plain link. Asserting on the
      // label alone would miss a rename, and asserting on the element alone
      // would miss a differently-named control, so this does both.
      expect(find.byType(button), findsNothing);
      expect(find.byType(a), findsNothing);
      expect(find.text('Sign in'), findsNothing);
      expect(find.text('Back to sign in'), findsNothing);
    });
  });
}
