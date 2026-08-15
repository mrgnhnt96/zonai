import 'package:jaspr/dom.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/components/theme/oauth_button.dart';

OAuthProviderPublic _github() {
  return const OAuthProviderPublic(
    id: 'github',
    displayName: 'GitHub',
    table: 'users',
    kind: OAuthProviderKind.github,
    background: '#24292F',
    foreground: '#FFFFFF',
    startPath: '/auth/oauth/start/github?table=users',
  );
}

void main() {
  testComponents('shows "Sign in with {displayName}"', (tester) async {
    tester.pumpComponent(OAuthProviderButton(provider: _github(), onClick: () {}));

    expect(find.text('Sign in with GitHub'), findsOneComponent);
  });

  testComponents('invokes onClick when clicked', (tester) async {
    var clicked = false;
    tester.pumpComponent(OAuthProviderButton(provider: _github(), onClick: () => clicked = true));

    await tester.click(find.tag('button'));

    expect(clicked, isTrue);
  });

  testComponents('carries the provider background/foreground as inline styles', (tester) async {
    tester.pumpComponent(OAuthProviderButton(provider: _github(), onClick: () {}));

    final buttons = find.byComponentPredicate((c) => c is button).evaluate();
    expect(buttons, hasLength(1));
    final rendered = buttons.single.component as button;
    expect(rendered.styles?.properties['background-color'], '#24292F');
    expect(rendered.styles?.properties['color'], '#FFFFFF');
  });

  testComponents('falls back to theme-neutral colors when the provider has none', (tester) async {
    const provider = OAuthProviderPublic(
      id: 'acme',
      displayName: 'Acme SSO',
      table: 'users',
      kind: OAuthProviderKind.custom,
      startPath: '/auth/oauth/start/acme?table=users',
    );
    tester.pumpComponent(OAuthProviderButton(provider: provider, onClick: () {}));

    expect(find.text('Sign in with Acme SSO'), findsOneComponent);
    final buttons = find.byComponentPredicate((c) => c is button).evaluate();
    final rendered = buttons.single.component as button;
    // Neither key is a literal hex — they resolve through the css variable
    // tokens (`var(--zonai-surface)`/`var(--zonai-fg)`), not a hardcoded color.
    expect(rendered.styles?.properties['background-color'], isNot(startsWith('#')));
    expect(rendered.styles?.properties['color'], isNot(startsWith('#')));
  });
}
