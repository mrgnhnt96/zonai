import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

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
        AuthFormCard(
          children: [
            const ZonaiPageTitle('Sign in with code'),
            const ZonaiPageSubtitle('Enter your email and we\'ll send you a one-time code.'),
            if (_error case final error?) ZonaiErrorText(error),
            ZonaiTextField(
              id: 'sign-in-email',
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
                  label: 'Send code',
                  loadingLabel: 'Sending code…',
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
            _sendCode();
          }
        },
      },
    );
  }

  Component _buildCodeStep() {
    return form(
      [
        AuthFormCard(
          children: [
            AuthSentHeader(
              title: 'Check your email',
              subtitle: 'Enter the 6-digit code we sent to $_email.',
            ),
            if (_error case final error?) ZonaiErrorText(error),
            ZonaiTextField(
              id: 'sign-in-code',
              fieldLabel: 'Verification code',
              type: .text,
              autocomplete: 'one-time-code',
              placeholder: '000000',
              attributes: const {
                'inputmode': 'numeric',
                'maxlength': '6',
              },
              value: _code,
              onInput: (v) => setState(() => _code = v.trim()),
            ),
            AuthActions(
              children: [
                AuthSubmitButton(
                  label: 'Verify and sign in',
                  loadingLabel: 'Verifying…',
                  loading: _loading,
                ),
                ZonaiButton(
                  variant: ZonaiButtonVariant.secondary,
                  fullWidth: true,
                  disabled: _loading,
                  onClick: _useDifferentEmail,
                  child: .text('Use a different email'),
                ),
                ZonaiButton(
                  variant: ZonaiButtonVariant.secondary,
                  fullWidth: true,
                  disabled: _loading,
                  onClick: () {
                    if (!_loading) {
                      _sendCode();
                    }
                  },
                  child: .text(_loading ? 'Sending…' : 'Resend code'),
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
            _verifyCode();
          }
        },
      },
    );
  }
}
