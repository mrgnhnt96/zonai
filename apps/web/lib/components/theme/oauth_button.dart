import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../../constants/spacing.dart';
import '../../constants/theme.dart';
import 'oauth_icon.dart';

/// A "Sign in with {provider}" button, sized to sit in the same list as
/// `AuthMethodTile` (`auth_shell.dart`) without looking bolted on — same
/// full-width shape, corner radius, and border-on-neutral-background
/// language, with [OAuthProviderPublic.background]/[foreground] as the one
/// per-provider difference.
///
/// Carries no navigation of its own — [onClick] is supplied by the caller
/// (routing to [OAuthProviderPublic.startPath] is `oauth-dashboard-wiring`'s
/// job, not this leaf's).
class OAuthProviderButton extends StatelessComponent {
  const OAuthProviderButton({super.key, required this.provider, required this.onClick});

  final OAuthProviderPublic provider;
  final void Function() onClick;

  @override
  Component build(BuildContext context) {
    final background = provider.background != null ? Color(provider.background!) : surfaceColor;
    final foreground = provider.foreground != null ? Color(provider.foreground!) : fgColor;

    return button(
      type: .button,
      classes: 'z-oauth-button',
      styles: Styles(backgroundColor: background, color: foreground),
      onClick: onClick,
      [
        div(classes: 'z-oauth-button__badge', [OAuthProviderIcon(provider: provider, size: 18)]),
        span(classes: 'z-oauth-button__label', [.text('Sign in with ${provider.displayName}')]),
      ],
    );
  }
}

@css
List<StyleRule> get oauthButtonStyles => [
  css('.z-oauth-button').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    gap: Gap.all(ZonaiSpacing.s6),
    width: 100.percent,
    padding: .all(ZonaiSpacing.s8),
    cursor: .pointer,
    radius: .all(Radius.circular(12.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    fontWeight: .w600,
    fontSize: 0.9375.rem,
    outline: Outline(style: OutlineStyle.none),
    raw: const {'font': 'inherit', 'transition': 'filter 0.15s ease, box-shadow 0.15s ease'},
  ),
  css('.z-oauth-button:hover').styles(raw: const {'filter': 'brightness(0.97)'}),
  css('.z-oauth-button:focus-visible').styles(raw: const {'box-shadow': '0 0 0 3px var(--zonai-focus-ring)'}),
  css('.z-oauth-button__badge').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    width: 26.px,
    height: 26.px,
    radius: .all(Radius.circular(6.px)),
    backgroundColor: surfaceColor,
    border: .all(color: borderColor, width: 1.px, style: .solid),
    raw: const {'flex-shrink': '0'},
  ),
  css('.z-oauth-button__label').styles(raw: const {'line-height': '1.2'}),
];
