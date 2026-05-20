import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import 'sign_in_screen.dart';

/// OTP sign-in form (email, then verification code).
class OtpSignInScreen extends StatelessComponent {
  const OtpSignInScreen({super.key});

  @override
  Component build(BuildContext context) {
    return const SignInScreen(child: OtpSignInForm());
  }
}

enum _OtpStep { email, code }

class OtpSignInForm extends StatefulComponent {
  const OtpSignInForm({super.key});

  @override
  State<OtpSignInForm> createState() => OtpSignInFormState();
}

class OtpSignInFormState extends State<OtpSignInForm> {
  _OtpStep _step = _OtpStep.email;
  String _email = '';
  String _code = '';
  bool _loading = false;
  String? _error;

  Future<void> _sendCode() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read(authProvider.notifier).sendOtp(email: _email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _OtpStep.code;
        _code = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not send a code. Check your email and try again.';
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read(authProvider.notifier).verifyOtp(
        email: _email,
        code: _code,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Invalid or expired code. Try again or request a new code.';
      });
    }
  }

  void _useDifferentEmail() {
    setState(() {
      _step = _OtpStep.email;
      _code = '';
      _error = null;
    });
  }

  @override
  Component build(BuildContext context) {
    return switch (_step) {
      _OtpStep.email => _buildEmailStep(),
      _OtpStep.code => _buildCodeStep(),
    };
  }

  Component _buildEmailStep() {
    return form(
      [
        h1(classes: 'title', [.text('Sign in')]),
        p(classes: 'subtitle', [
          .text('Enter your email and we\'ll send you a one-time code.'),
        ]),
        if (_error case final error?) p(classes: 'error', [.text(error)]),
        div(classes: 'field', [
          label(htmlFor: 'sign-in-email', classes: 'label', [.text('Email')]),
          input<String>(
            id: 'sign-in-email',
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
          [.text(_loading ? 'Sending code…' : 'Send code')],
        ),
      ],
      classes: 'card',
      events: {
        'submit': (web.Event event) {
          event.preventDefault();
          if (!_loading) {
            _sendCode();
          }
        },
      },
    );
  }

  Component _buildCodeStep() {
    return form(
      [
        h1(classes: 'title', [.text('Check your email')]),
        p(classes: 'subtitle', [
          .text('Enter the code we sent to $_email.'),
        ]),
        if (_error case final error?) p(classes: 'error', [.text(error)]),
        div(classes: 'field', [
          label(htmlFor: 'sign-in-code', classes: 'label', [.text('Code')]),
          input<String>(
            id: 'sign-in-code',
            type: .text,
            name: 'code',
            classes: 'input',
            attributes: const {
              'autocomplete': 'one-time-code',
              'inputmode': 'numeric',
              'maxlength': '6',
            },
            value: _code,
            onInput: (v) => setState(() => _code = v.trim()),
          ),
        ]),
        button(
          classes: 'submit',
          type: .submit,
          disabled: _loading,
          [.text(_loading ? 'Verifying…' : 'Verify and sign in')],
        ),
        button(
          classes: 'otp-secondary',
          type: .button,
          disabled: _loading,
          onClick: _useDifferentEmail,
          [.text('Use a different email')],
        ),
        button(
          classes: 'otp-secondary',
          type: .button,
          disabled: _loading,
          onClick: () {
            if (!_loading) {
              _sendCode();
            }
          },
          [.text(_loading ? 'Sending…' : 'Resend code')],
        ),
      ],
      classes: 'card',
      events: {
        'submit': (web.Event event) {
          event.preventDefault();
          if (!_loading) {
            _verifyCode();
          }
        },
      },
    );
  }
}
