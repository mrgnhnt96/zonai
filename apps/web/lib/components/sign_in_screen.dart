import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import '../auth/supported_auth_types_provider.dart';
import 'theme/theme_components.dart';

/// Shared layout for sign-in screens (centered auth page with branding).
class SignInScreen extends StatelessComponent {
  const SignInScreen({super.key, required this.child, this.tagline = 'Sign in to your workspace'});

  final Component child;
  final String tagline;

  @override
  Component build(BuildContext context) {
    return AuthPage(tagline: tagline, child: child);
  }
}

/// Lists available sign-in methods.
class AuthTypePickerScreen extends StatelessComponent {
  const AuthTypePickerScreen({super.key});

  @override
  Component build(BuildContext context) {
    final authTypes = context.watch(supportedAuthTypesProvider);
    return SignInScreen(
      tagline: 'Choose how you want to sign in',
      child: AuthFormCard(
        children: [
          const ZonaiPageTitle('Welcome back'),
          const ZonaiPageSubtitle('Pick a sign-in method to continue.'),
          div(classes: ZonaiClasses.authMethods, [
            for (final authType in authTypes)
              AuthMethodTile(
                title: _titleFor(authType),
                description: _descriptionFor(authType),
                onSelect: () {
                  context.goApp(AuthRoutes.forType(authType));
                },
              ),
          ]),
        ],
      ),
    );
  }

  static String _titleFor(AuthType authType) {
    return switch (authType) {
      AuthType.password => 'Email & password',
      AuthType.otp => 'Email code',
      AuthType.magicLink => 'Magic link',
    };
  }

  static String _descriptionFor(AuthType authType) {
    return switch (authType) {
      AuthType.password => 'Sign in with the email and password on your account.',
      AuthType.otp => 'We\'ll send a one-time code to your inbox.',
      AuthType.magicLink => 'We\'ll email you a secure link — no password needed.',
    };
  }
}

/// Password sign-in form.
class PasswordSignInScreen extends StatelessComponent {
  const PasswordSignInScreen({super.key});

  @override
  Component build(BuildContext context) {
    return const SignInScreen(child: PasswordSignInForm());
  }
}

/// Interactive password sign-in controls (hydrated via [AppShell]).
class PasswordSignInForm extends StatefulComponent {
  const PasswordSignInForm({super.key});

  @override
  State<PasswordSignInForm> createState() => PasswordSignInFormState();
}

class PasswordSignInFormState extends State<PasswordSignInForm> {
  String _email = '';
  String _password = '';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read(authProvider.notifier).signInWithPassword(email: _email, password: _password);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign in failed. Check your email and password.';
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return form(
      [
        AuthFormCard(
          children: [
            const ZonaiPageTitle('Sign in'),
            const ZonaiPageSubtitle('Enter your credentials to continue.'),
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
            ZonaiTextField(
              id: 'sign-in-password',
              fieldLabel: 'Password',
              type: .password,
              autocomplete: 'current-password',
              value: _password,
              onInput: (v) => setState(() => _password = v),
            ),
            AuthActions(
              children: [AuthSubmitButton(label: 'Sign in', loadingLabel: 'Signing in…', loading: _loading)],
            ),
            AuthTextLink(
              label: 'Forgot password?',
              onClick: () {
                context.goApp(AuthRoutes.resetPasswordRequest);
              },
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
