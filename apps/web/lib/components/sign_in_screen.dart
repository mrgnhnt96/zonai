import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../constants/theme.dart';

/// Server-rendered layout; delegates interactivity to [SignInForm].
class SignInScreen extends StatelessComponent {
  const SignInScreen({super.key});

  @override
  Component build(BuildContext context) {
    return main_(classes: 'sign-in', [const SignInForm()]);
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
      css('.submit').styles(
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
      css('.submit:hover').styles(backgroundColor: const Color('#014a84')),
    ]),
  ];
}

/// Interactive sign-in controls (hydrated on the client).
@client
class SignInForm extends StatefulComponent {
  const SignInForm({super.key});

  @override
  State<SignInForm> createState() => SignInFormState();
}

class SignInFormState extends State<SignInForm> {
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
          // Wire-up to auth when backend exists.
        },
        [.text('Sign in')],
      ),
    ]);
  }
}
