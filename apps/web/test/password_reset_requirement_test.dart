import 'package:jaspr/dom.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_client/zonai_client.dart' show PasswordResetRequiredException;
import 'package:zonai_web/components/forced_password_reset_form.dart';
import 'package:zonai_web/utils/password_reset_requirement_summary.dart';

/// The decisions the forced-reset surfaces make about a wire payload, tested
/// where they are decisions rather than pixels — the same split
/// `admin_members_test.dart` and `reset_password_done_test.dart` use.
void main() {
  group('the sign-in copy for a forced reset', () {
    test('names the cause when the server sent one it knows', () {
      // The wording is the difference between an operator who understands why
      // they are here and one who thinks the dashboard is broken. Each reason
      // gets its own sentence because "you must reset" is true for all four and
      // useful for none.
      expect(
        forcedPasswordResetSubtitle('temporaryPassword'),
        'Your current password was set by someone else. Choose your own to continue.',
      );
      expect(
        forcedPasswordResetSubtitle('compromised'),
        'This password may be known to someone else. Choose a new one to continue.',
      );
      expect(
        forcedPasswordResetSubtitle('passwordPolicy'),
        'Your password needs renewing. Choose a new one to continue.',
      );
    });

    test('falls back to a sentence that is true for a reason it has never '
        'heard of', () {
      // A NEWER server may send a value this build predates. Rendering the raw
      // identifier would leak an implementation name into a sign-in screen,
      // and there is no honest wording to guess — so the fallback says only
      // what is certainly true.
      final unknown = forcedPasswordResetSubtitle('quantumEntanglement');

      expect(unknown, 'Your account must set a new password before signing in.');
      expect(unknown, isNot(contains('quantum')));
      expect(unknown, forcedPasswordResetSubtitle('adminForced'));
    });

    test('survives an empty reason', () {
      // `PasswordResetRequiredException.reason` is empty when the server sent
      // none, which is a shape the client explicitly allows.
      expect(forcedPasswordResetSubtitle(''), 'Your account must set a new password before signing in.');
    });

    test('the rejection message points at the likely cause', () {
      // The overwhelmingly likely rejection is the 422 for reusing the current
      // password. Naming it is the difference between trying another password
      // and giving up.
      expect(forcedPasswordResetError(), contains('cannot be the password you just signed in with'));
    });
  });

  group('the requirement banner in the row detail panel', () {
    test('names the CLI when the CLI set it', () {
      // `'cli'` is what `zonai db admin` writes and an admin id is what the
      // dashboard writes. The distinction is "one of us did this in the
      // dashboard" versus "someone was on the server box", which is exactly
      // what an operator investigating a lockout needs.
      expect(
        passwordResetRequirementSummary(const {'reason': 'compromised', 'createdBy': 'cli', 'createdAt': null}),
        'Set from the command line — the password may be known to someone else.',
      );
    });

    test('names the admin when an admin set it', () {
      expect(
        passwordResetRequirementSummary(const {'reason': 'adminForced', 'createdBy': 'usr_123', 'createdAt': null}),
        'Set by usr_123 — an administrator.',
      );
    });

    test('does not invent an author when the row records none', () {
      // Nothing that sets a requirement omits `created_by`, so a null here
      // means a row written by a path that forgot to say. Claiming an author
      // would be a fabrication in the one column that exists to answer "who
      // locked this account out".
      expect(
        passwordResetRequirementSummary(const {'reason': 'adminForced', 'createdBy': null}),
        'Set by an unrecorded caller — an administrator.',
      );
    });

    test('omits an unknown reason rather than rendering the raw value', () {
      final summary = passwordResetRequirementSummary(const {'reason': 'quantumEntanglement', 'createdBy': 'cli'});

      expect(summary, 'Set from the command line.');
      expect(summary, isNot(contains('quantum')));
    });

    test('includes the day when the row carries a parseable timestamp', () {
      expect(
        passwordResetRequirementSummary({
          'reason': 'adminForced',
          'createdBy': 'cli',
          'createdAt': DateTime.utc(2026, 8, 24, 12).toIso8601String(),
        }),
        contains('2026-08-2'),
      );
    });

    test('drops an unparseable timestamp instead of failing', () {
      // This crosses a wire. A malformed value must degrade to a shorter
      // sentence, not throw inside a panel build.
      expect(
        passwordResetRequirementSummary(const {'reason': 'adminForced', 'createdBy': 'cli', 'createdAt': 'not a date'}),
        'Set from the command line — an administrator.',
      );
    });
  });

  group('ForcedPasswordResetForm', () {
    testComponents('asks for a new password rather than reporting a failure', (tester) async {
      // Pumped directly, like ResetPasswordDoneCard: the state behind it sits
      // past an async client call, and a test that faked the client to reach
      // it would be pinning the mock rather than the markup.
      tester.pumpComponent(
        const ForcedPasswordResetForm(
          email: 'admin@example.com',
          refusal: PasswordResetRequiredException(
            resetToken: 'tok',
            expiresIn: Duration(minutes: 15),
            reason: 'temporaryPassword',
            message: 'This account must set a new password before signing in',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Choose a new password'), findsOneComponent);
      expect(
        find.text('Your current password was set by someone else. Choose your own to continue.'),
        findsOneComponent,
      );

      // The credentials were CORRECT. Any wording implying otherwise sends an
      // operator to check a password that is not the problem.
      expect(find.text('Sign in failed. Check your email and password.'), findsNothing);
    });

    testComponents('the button says it will sign you in, because it does', (tester) async {
      // Unlike the emailed reset, which ends signed OUT on purpose. If this
      // label ever drifts to "Update password" the two flows have silently
      // converged and the admin is left at a dead end.
      tester.pumpComponent(
        const ForcedPasswordResetForm(
          email: 'admin@example.com',
          refusal: PasswordResetRequiredException(
            resetToken: 'tok',
            expiresIn: Duration(minutes: 15),
            reason: 'adminForced',
            message: 'msg',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Set password and sign in'), findsOneComponent);
    });
  });
}
