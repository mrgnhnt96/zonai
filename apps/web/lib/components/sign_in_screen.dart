import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import '../auth/supported_auth_types_provider.dart';
import '../constants/theme.dart';

/// Shared layout for sign-in screens.
class SignInScreen extends StatelessComponent {
  const SignInScreen({super.key, required this.child});

  final Component child;

  @override
  Component build(BuildContext context) {
    return main_(classes: 'sign-in', [child]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.sign-in', [
      css('&').styles(
        flex: Flex(grow: 1, shrink: 0),
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        padding: .all(24.px),
      ),
      css('.card').styles(
        width: 100.percent,
        maxWidth: 400.px,
        backgroundColor: surfaceColor,
        padding: .all(32.px),
        radius: .all(Radius.circular(16.px)),
        shadow: BoxShadow(
          offsetX: Unit.zero,
          offsetY: 12.px,
          blur: 40.px,
          spread: (-8).px,
          color: Colors.black.withOpacity(0.08),
        ),
      ),
      css('.title').styles(
        margin: .only(bottom: 8.px),
        fontSize: 1.5.rem,
        fontWeight: .w600,
      ),
      css('.subtitle').styles(
        margin: .only(bottom: 28.px),
        fontSize: 0.95.rem,
        color: const Color('#64748b'),
      ),
      css('.field').styles(margin: .only(bottom: 18.px)),
      css('.label').styles(
        display: .block,
        margin: .only(bottom: 6.px),
        fontSize: 0.875.rem,
        fontWeight: .w600,
      ),
      css('.input').styles(
        display: .block,
        width: 100.percent,
        padding: .symmetric(horizontal: 12.px, vertical: 10.px),
        radius: .all(Radius.circular(8.px)),
        border: .all(color: borderColor, width: 1.px, style: .solid),
        fontSize: 1.rem,
        outline: Outline(style: OutlineStyle.none),
      ),
      css('.input:focus-visible').styles(
        outline: Outline(style: OutlineStyle.solid, width: OutlineWidth(2.px), color: primaryColor, offset: 2.px),
      ),
      css('.submit, .auth-type').styles(
        width: 100.percent,
        margin: .only(top: 8.px),
        padding: .symmetric(vertical: 12.px),
        cursor: .pointer,
        radius: .all(Radius.circular(8.px)),
        border: Border.none,
        fontWeight: .w600,
        fontSize: 1.rem,
        color: Colors.white,
        backgroundColor: primaryColor,
      ),
      css('.submit:hover, .auth-type:hover').styles(backgroundColor: const Color('#014a84')),
      css('.auth-type + .auth-type').styles(margin: .only(top: 12.px)),
    ]),
  ];
}

/// Lists available sign-in methods.
class AuthTypePickerScreen extends StatelessComponent {
  const AuthTypePickerScreen({super.key});

  @override
  Component build(BuildContext context) {
    final authTypes = context.watch(supportedAuthTypesProvider);
    return SignInScreen(
      child: div(classes: 'card', [
        h1(classes: 'title', [.text('Sign in')]),
        p(classes: 'subtitle', [
          .text('Choose how you want to sign in.'),
        ]),
        for (final authType in authTypes)
          button(
            classes: 'auth-type',
            type: .button,
            onClick: () {
              context.read(authRouteProvider.notifier).navigateTo(
                AuthRoutes.forType(authType),
              );
            },
            [.text(_labelFor(authType))],
          ),
      ]),
    );
  }

  static String _labelFor(AuthType authType) {
    return switch (authType) {
      AuthType.password => 'Email & password',
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

  @override
  Component build(BuildContext context) {
    return div(classes: 'card', [
      h1(classes: 'title', [.text('Sign in')]),
      p(classes: 'subtitle', [.text('Enter your credentials to continue.')]),
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
      div(classes: 'field', [
        label(htmlFor: 'sign-in-password', classes: 'label', [.text('Password')]),
        input<String>(
          id: 'sign-in-password',
          type: .password,
          name: 'password',
          classes: 'input',
          attributes: const {'autocomplete': 'current-password'},
          value: _password,
          onInput: (v) => setState(() => _password = v),
        ),
      ]),
      button(
        classes: 'submit',
        type: .button,
        onClick: () {
          context.read(authProvider.notifier).signIn();
        },
        [.text('Sign in')],
      ),
    ]);
  }
}
