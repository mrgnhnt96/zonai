import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_client/zonai_client.dart' show PasswordResetRequiredException;

import '../auth/auth_provider.dart';
import 'theme/theme_components.dart';

/// Choose a new password, from inside the sign-in screen, without an email.
///
/// Reached only when `POST /auth/admin` answered 403 with a reset ticket
/// (`docs/force-password-reset-design.md` §7). The credentials were CORRECT --
/// this is not a failed sign-in -- so the copy says so rather than implying
/// the operator mistyped something.
///
/// Deliberately NOT [ResetPasswordConfirmForm], which serves the emailed link:
///
///   * that one reads its token from `?s=` in the URL; this one is handed a
///     ticket that arrived in a response body and never touches the address
///     bar, which is the point of a credential with a 15-minute life.
///   * that one ends on [ResetPasswordDoneCard], which offers no way onward
///     BECAUSE an emailed link reaches whoever owns the account on any auth
///     table, and the only sign-in this app could offer them is somebody
///     else's admin panel. Here the caller is already at the dashboard's own
///     door, so the honest ending is the opposite one: signed in.
class ForcedPasswordResetForm extends StatefulComponent {
  const ForcedPasswordResetForm({super.key, required this.email, required this.refusal});

  /// The address that was just refused. Carried rather than re-asked: the
  /// second half of this flow signs in again, and asking for an address the
  /// screen already holds invites a typo that reads as a wrong password.
  final String email;

  final PasswordResetRequiredException refusal;

  @override
  State<ForcedPasswordResetForm> createState() => ForcedPasswordResetFormState();
}

class ForcedPasswordResetFormState extends State<ForcedPasswordResetForm> {
  String _password = '';
  String _confirmPassword = '';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_loading) return;

    if (_password.isEmpty) {
      setState(() => _error = 'Enter a new password.');
      return;
    }

    if (_password != _confirmPassword) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context
          .read(authProvider.notifier)
          .completeForcedPasswordReset(refusal: component.refusal, email: component.email, newPassword: _password);
    } catch (_) {
      // The ticket SURVIVES a rejected password -- the server consumes the
      // challenge only after every check that can still reject the submission,
      // deliberately, because on this path there is no email to re-request.
      // So this stays on the same form with the same ticket rather than
      // sending the operator back to sign-in to earn a new one.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = forcedPasswordResetError();
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return form(
      [
        AuthFormCard(
          children: [
            const ZonaiPageTitle('Choose a new password'),
            ZonaiPageSubtitle(forcedPasswordResetSubtitle(component.refusal.reason)),
            if (_error case final error?) ZonaiErrorText(error),
            ZonaiTextField(
              id: 'forced-new-password',
              fieldLabel: 'New password',
              type: .password,
              autocomplete: 'new-password',
              value: _password,
              onInput: (v) => setState(() {
                _password = v;
                _error = null;
              }),
            ),
            ZonaiTextField(
              id: 'forced-confirm-password',
              fieldLabel: 'Confirm password',
              type: .password,
              autocomplete: 'new-password',
              value: _confirmPassword,
              onInput: (v) => setState(() {
                _confirmPassword = v;
                _error = null;
              }),
            ),
            AuthActions(
              children: [
                AuthSubmitButton(label: 'Set password and sign in', loadingLabel: 'Signing in…', loading: _loading),
              ],
            ),
          ],
        ),
      ],
      events: {
        'submit': (web.Event event) {
          event.preventDefault();
          if (!_loading) {
            _submit();
          }
        },
      },
    );
  }
}

/// What to tell the operator about why they are here.
///
/// A pure function so the wording can be pinned by a test without pumping a
/// component through an async client call. The reason arrives as a STRING and
/// not an enum -- a newer server may send one this build has never heard of --
/// so the fallback is a sentence that is true whatever it says, never a
/// rendered raw identifier.
String forcedPasswordResetSubtitle(String reason) {
  return switch (reason) {
    'temporaryPassword' => 'Your current password was set by someone else. Choose your own to continue.',
    'compromised' => 'This password may be known to someone else. Choose a new one to continue.',
    'passwordPolicy' => 'Your password needs renewing. Choose a new one to continue.',
    'adminForced' || _ => 'Your account must set a new password before signing in.',
  };
}

/// The message for a rejected submission.
///
/// The overwhelmingly likely cause is the one the server answers 422 for --
/// the password the account already has -- and naming it is the difference
/// between an operator trying a different password and an operator concluding
/// the dashboard is broken. Phrased so it is not a lie if the cause was
/// something else.
String forcedPasswordResetError() {
  return 'Could not set that password. Choose a different one — it cannot be the '
      'password you just signed in with.';
}
