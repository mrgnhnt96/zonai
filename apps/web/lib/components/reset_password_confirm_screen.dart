import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

/// Sets a new password from a reset link query parameter.
class ResetPasswordConfirmScreen extends StatelessComponent {
  const ResetPasswordConfirmScreen({super.key});

  @override
  Component build(BuildContext context) {
    return const SignInScreen(tagline: 'Choose a new password', child: ResetPasswordConfirmForm());
  }
}

class ResetPasswordConfirmForm extends StatefulComponent {
  const ResetPasswordConfirmForm({super.key});

  @override
  State<ResetPasswordConfirmForm> createState() => ResetPasswordConfirmFormState();
}

class ResetPasswordConfirmFormState extends State<ResetPasswordConfirmForm> {
  String? _token;
  String _password = '';
  String _confirmPassword = '';
  bool _loading = false;
  bool _success = false;
  bool _tokenChecked = false;
  String? _linkError;
  String? _error;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_loadFromUrl);
  }

  void _loadFromUrl() {
    final token = Uri.parse(context.url).queryParameters['s'];
    setState(() {
      _tokenChecked = true;
      if (token == null || token.isEmpty) {
        _linkError = 'This reset link is invalid or incomplete.';
        return;
      }
      _token = token;
    });
  }

  Future<void> _submit() async {
    if (_loading || _token == null) return;

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
      await context.read(authProvider.notifier).confirmResetPassword(token: _token!, newPassword: _password);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not reset your password. The link may be invalid or expired.';
      });
    }
  }

  void _returnToSignIn() {
    context.goApp(AuthRoutes.forType(.password));
  }

  @override
  Component build(BuildContext context) {
    if (_success) {
      return AuthFormCard(
        children: [
          AuthSentHeader(
            icon: '✓',
            title: 'Password updated',
            subtitle: 'Your password has been reset. You can sign in with your new password.',
          ),
          AuthActions(
            children: [ZonaiButton(fullWidth: true, onClick: _returnToSignIn, child: .text('Sign in'))],
          ),
        ],
      );
    }

    if (_linkError case final linkError?) {
      return AuthFormCard(
        children: [
          const ZonaiPageTitle('Reset password'),
          ZonaiErrorText(linkError),
          AuthActions(
            children: [ZonaiButton(fullWidth: true, onClick: _returnToSignIn, child: .text('Back to sign in'))],
          ),
        ],
      );
    }

    if (!_tokenChecked || _token == null) {
      return AuthFormCard(
        children: [const ZonaiPageTitle('Choose a new password'), const ZonaiPageSubtitle('Loading reset link…')],
      );
    }

    return form(
      [
        AuthFormCard(
          children: [
            const ZonaiPageTitle('Choose a new password'),
            const ZonaiPageSubtitle('Enter a new password for your account.'),
            if (_error case final error?) ZonaiErrorText(error),
            ZonaiTextField(
              id: 'new-password',
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
              id: 'confirm-password',
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
              children: [AuthSubmitButton(label: 'Update password', loadingLabel: 'Updating…', loading: _loading)],
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
