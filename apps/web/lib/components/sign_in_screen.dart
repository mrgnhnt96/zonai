import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_client/zonai_client.dart' show PasswordResetRequiredException;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import '../auth/supported_auth_types_provider.dart';
import '../constants/spacing.dart';
import 'forced_password_reset_form.dart';
import 'oauth_sign_in_screen.dart';
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
              // OAuth is a list of providers, not a single destination: a tile
              // that only leads to another list of buttons would be a hop for
              // nothing. The buttons render inline, under the same heading the
              // tiles would have carried.
              if (authType == AuthType.oauth)
                OAuthMethodGroup(title: _titleFor(authType), description: _descriptionFor(authType))
              else
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
      AuthType.oauth => 'Continue with a provider',
    };
  }

  static String _descriptionFor(AuthType authType) {
    return switch (authType) {
      AuthType.password => 'Sign in with the email and password on your account.',
      AuthType.otp => 'We\'ll send a one-time code to your inbox.',
      AuthType.magicLink => 'We\'ll email you a secure link — no password needed.',
      // Deliberately names no provider: which ones exist is the developer's
      // `oauthProviders` list, and the buttons below say so themselves.
      AuthType.oauth => 'Use an account you already have with one of these providers.',
    };
  }
}

/// The OAuth entry in the method list: a tile-shaped heading plus one button
/// per provider from [oauthProvidersProvider].
class OAuthMethodGroup extends StatelessComponent {
  const OAuthMethodGroup({super.key, required this.title, required this.description});

  final String title;
  final String description;

  @override
  Component build(BuildContext context) {
    return div(classes: 'z-auth-oauth-group', [
      span(classes: ZonaiClasses.authMethodTitle, [.text(title)]),
      span(classes: ZonaiClasses.authMethodDesc, [.text(description)]),
      OAuthProviderButtons(onSelect: startOAuthFlow),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css(
      '.z-auth-oauth-group',
    ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s4), width: 100.percent),
  ];
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

  /// Set when the server refuses with a 403 carrying a reset ticket. Its
  /// presence is what swaps this form for [ForcedPasswordResetForm] -- an
  /// admin who is forced to reset and cannot finish it HERE has no dashboard,
  /// and no email need reach them for this to work.
  PasswordResetRequiredException? _resetRequired;

  Future<void> _submit() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read(authProvider.notifier).signInWithPassword(email: _email, password: _password);
    } on PasswordResetRequiredException catch (refusal) {
      // Caught BEFORE the generic clause below, which is the whole point.
      // "Check your email and password" is exactly wrong here: the credentials
      // were correct, and the response carries the one thing needed to
      // recover.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _resetRequired = refusal;
      });
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
    if (_resetRequired case final refusal?) {
      return ForcedPasswordResetForm(email: _email, refusal: refusal);
    }

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
