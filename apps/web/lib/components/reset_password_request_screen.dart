import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import 'sign_in_screen.dart';

/// Form to request a password reset email.
class ResetPasswordRequestScreen extends StatelessComponent {
  const ResetPasswordRequestScreen({super.key});

  @override
  Component build(BuildContext context) {
    return const SignInScreen(child: ResetPasswordRequestForm());
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
        h1(classes: 'title', [.text('Reset password')]),
        p(classes: 'subtitle', [
          .text('Enter your email and we\'ll send you a link to reset your password.'),
        ]),
        if (_error case final error?) p(classes: 'error', [.text(error)]),
        div(classes: 'field', [
          label(htmlFor: 'reset-email', classes: 'label', [.text('Email')]),
          input<String>(
            id: 'reset-email',
            type: .email,
            name: 'email',
            classes: 'input',
            attributes: const {'autocomplete': 'email'},
            value: _email,
            onInput: (v) => setState(() => _email = v),
          ),
        ]),
        button(
          classes: 'submit',
          type: .submit,
          disabled: _loading,
          [.text(_loading ? 'Sending link…' : 'Send reset link')],
        ),
        button(
          classes: 'otp-secondary',
          type: .button,
          onClick: _returnToSignIn,
          [.text('Back to sign in')],
        ),
      ],
      classes: 'card',
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
    return div(classes: 'card', [
      h1(classes: 'title', [.text('Check your email')]),
      p(classes: 'subtitle', [
        .text(
          'If an account exists for $_email, we sent a password reset link. '
          'Open the link to choose a new password.',
        ),
      ]),
      button(
        classes: 'otp-secondary',
        type: .button,
        onClick: () {
          setState(() {
            _step = _ResetPasswordRequestStep.email;
            _error = null;
          });
        },
        [.text('Use a different email')],
      ),
      button(
        classes: 'otp-secondary',
        type: .button,
        disabled: _loading,
        onClick: () {
          if (!_loading) {
            _sendResetLink();
          }
        },
        [.text(_loading ? 'Sending…' : 'Resend link')],
      ),
      button(
        classes: 'otp-secondary',
        type: .button,
        onClick: _returnToSignIn,
        [.text('Back to sign in')],
      ),
    ]);
  }
}
