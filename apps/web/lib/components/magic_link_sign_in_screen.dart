import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import 'sign_in_screen.dart';

/// Magic link sign-in form (email, then check-your-email confirmation).
class MagicLinkSignInScreen extends StatelessComponent {
  const MagicLinkSignInScreen({super.key});

  @override
  Component build(BuildContext context) {
    return const SignInScreen(child: MagicLinkSignInForm());
  }
}

enum _MagicLinkStep { email, sent }

class MagicLinkSignInForm extends StatefulComponent {
  const MagicLinkSignInForm({super.key});

  @override
  State<MagicLinkSignInForm> createState() => MagicLinkSignInFormState();
}

class MagicLinkSignInFormState extends State<MagicLinkSignInForm> {
  _MagicLinkStep _step = _MagicLinkStep.email;
  String _email = '';
  bool _loading = false;
  String? _error;

  Future<void> _sendLink() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read(authProvider.notifier).sendMagicLink(email: _email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _MagicLinkStep.sent;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not send a sign-in link. Check your email and try again.';
      });
    }
  }

  void _useDifferentEmail() {
    setState(() {
      _step = _MagicLinkStep.email;
      _error = null;
    });
  }

  @override
  Component build(BuildContext context) {
    return switch (_step) {
      _MagicLinkStep.email => _buildEmailStep(),
      _MagicLinkStep.sent => _buildSentStep(),
    };
  }

  Component _buildEmailStep() {
    return form(
      [
        h1(classes: 'title', [.text('Sign in')]),
        p(classes: 'subtitle', [
          .text('Enter your email and we\'ll send you a sign-in link.'),
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
          [.text(_loading ? 'Sending link…' : 'Send sign-in link')],
        ),
      ],
      classes: 'card',
      events: {
        'submit': (web.Event event) {
          event.preventDefault();
          if (!_loading) {
            _sendLink();
          }
        },
      },
    );
  }

  Component _buildSentStep() {
    return div(classes: 'card', [
      h1(classes: 'title', [.text('Check your email')]),
      p(classes: 'subtitle', [
        .text('We sent a sign-in link to $_email. Open the link to continue.'),
      ]),
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
            _sendLink();
          }
        },
        [.text(_loading ? 'Sending…' : 'Resend link')],
      ),
    ]);
  }
}
