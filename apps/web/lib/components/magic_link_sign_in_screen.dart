import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

/// Magic link sign-in form (email, then check-your-email confirmation).
class MagicLinkSignInScreen extends StatelessComponent {
  const MagicLinkSignInScreen({super.key});

  @override
  Component build(BuildContext context) {
    return const SignInScreen(
      tagline: 'Passwordless sign-in',
      child: MagicLinkSignInForm(),
    );
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
        AuthFormCard(
          children: [
            const ZonaiPageTitle('Magic link'),
            const ZonaiPageSubtitle('Enter your email and we\'ll send you a sign-in link.'),
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
                  label: 'Send sign-in link',
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
            _sendLink();
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
          subtitle: 'We sent a sign-in link to $_email. Open the link to continue.',
        ),
        AuthActions(
          children: [
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
                  _sendLink();
                }
              },
              child: .text(_loading ? 'Sending…' : 'Resend link'),
            ),
          ],
        ),
      ],
    );
  }
}
