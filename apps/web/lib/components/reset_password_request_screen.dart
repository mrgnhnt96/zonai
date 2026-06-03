import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

/// Form to request a password reset email.
class ResetPasswordRequestScreen extends StatelessComponent {
  const ResetPasswordRequestScreen({super.key});

  @override
  Component build(BuildContext context) {
    return const SignInScreen(
      tagline: 'Reset your password',
      child: ResetPasswordRequestForm(),
    );
  }
}

enum _ResetPasswordRequestStep { email, sent }

class ResetPasswordRequestForm extends StatefulComponent {
  const ResetPasswordRequestForm({super.key});

  @override
  State<ResetPasswordRequestForm> createState() => ResetPasswordRequestFormState();
}

class ResetPasswordRequestFormState extends State<ResetPasswordRequestForm> {
  _ResetPasswordRequestStep _step = _ResetPasswordRequestStep.email;
  String _email = '';
  bool _loading = false;
  String? _error;

  Future<void> _sendResetLink() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read(authProvider.notifier).sendResetPassword(email: _email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _ResetPasswordRequestStep.sent;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not send a reset link. Check your email and try again.';
      });
    }
  }

  void _returnToSignIn() {
    context.read(authRouteProvider.notifier).navigateTo(AuthRoutes.forType(.password));
  }

  @override
  Component build(BuildContext context) {
    return switch (_step) {
      _ResetPasswordRequestStep.email => _buildEmailStep(),
      _ResetPasswordRequestStep.sent => _buildSentStep(),
    };
  }

  Component _buildEmailStep() {
    return form(
      [
        AuthFormCard(
          children: [
            const ZonaiPageTitle('Reset password'),
            const ZonaiPageSubtitle('Enter your email and we\'ll send you a link to reset your password.'),
            if (_error case final error?) ZonaiErrorText(error),
            ZonaiTextField(
              id: 'reset-email',
              fieldLabel: 'Email',
              type: .email,
              autocomplete: 'email',
              placeholder: 'you@example.com',
              value: _email,
              onInput: (v) => setState(() => _email = v),
            ),
            AuthActions(
              children: [
                AuthSubmitButton(
                  label: 'Send reset link',
                  loadingLabel: 'Sending link…',
                  loading: _loading,
                ),
              ],
            ),
          ],
        ),
      ],
      events: {
        'submit': (web.Event event) {
          event.preventDefault();
          if (!_loading) {
            _sendResetLink();
          }
        },
      },
    );
  }

  Component _buildSentStep() {
    return AuthFormCard(
      children: [
        AuthSentHeader(
          title: 'Check your email',
          subtitle:
              'If an account exists for $_email, we sent a password reset link. '
              'Open the link to choose a new password.',
        ),
        AuthActions(
          children: [
            ZonaiButton(
              variant: ZonaiButtonVariant.secondary,
              fullWidth: true,
              onClick: () {
                setState(() {
                  _step = _ResetPasswordRequestStep.email;
                  _error = null;
                });
              },
              child: .text('Use a different email'),
            ),
            ZonaiButton(
              variant: ZonaiButtonVariant.secondary,
              fullWidth: true,
              disabled: _loading,
              onClick: () {
                if (!_loading) {
                  _sendResetLink();
                }
              },
              child: .text(_loading ? 'Sending…' : 'Resend link'),
            ),
            ZonaiButton(
              variant: ZonaiButtonVariant.secondary,
              fullWidth: true,
              onClick: _returnToSignIn,
              child: .text('Back to sign in'),
            ),
          ],
        ),
      ],
    );
  }
}
