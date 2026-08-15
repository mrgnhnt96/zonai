import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import '../../constants/theme.dart';
import 'oauth_marks.dart';
import 'oauth_sanitize.dart';

/// Resolves and renders one [OAuthProviderPublic]'s sign-in icon.
///
/// Resolution order, each rung independently testable:
///
/// 1. [OAuthProviderPublic.kind] is a known built-in (not
///    [OAuthProviderKind.custom]) -> the bundled mark from `oauth_marks.dart`.
///    Built-ins never trust a caller-supplied [OAuthProviderPublic.iconUrl]
///    or [OAuthProviderPublic.iconSvg] — see [OAuthIcon]'s doc comment for
///    why (a compromised/unreachable URL must never be able to impersonate a
///    well-known provider's logo).
/// 2. [OAuthProviderPublic.iconSvg] — passed through [sanitizeInlineSvg]
///    first. A value that fails sanitization is treated the same as absent
///    and falls through to the next rung; [OAuthProviderIcon] never puts an
///    unvalidated string in the DOM.
/// 3. [OAuthProviderPublic.iconUrl] — rendered as an `<img>`.
/// 4. Nothing — a letter tile using the provider's first initial, matching
///    [AuthBrand]'s no-logo fallback in `auth_shell.dart`.
class OAuthProviderIcon extends StatelessComponent {
  const OAuthProviderIcon({super.key, required this.provider, this.size = 20});

  final OAuthProviderPublic provider;

  /// Rendered width/height in pixels. Bundled marks and inline SVG scale to
  /// this via their own `viewBox`; the `<img>` and letter-tile rungs are
  /// sized to match.
  final double size;

  @override
  Component build(BuildContext context) {
    if (provider.kind != OAuthProviderKind.custom) {
      return oauthBrandMark(provider.kind, size: size);
    }

    final iconSvg = provider.iconSvg;
    if (iconSvg != null && iconSvg.isNotEmpty) {
      final sanitized = sanitizeInlineSvg(iconSvg);
      if (sanitized != null) {
        return div(classes: 'z-oauth-mark', styles: Styles(width: size.px, height: size.px), [RawText(sanitized)]);
      }
    }

    final iconUrl = provider.iconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return img(
        src: iconUrl,
        alt: provider.displayName,
        width: size.round(),
        height: size.round(),
        classes: 'z-oauth-icon-img',
      );
    }

    return OAuthLetterTile(displayName: provider.displayName, size: size);
  }
}

/// The no-icon fallback: an initial-letter tile, matching the letter tile
/// `AuthBrand` (`auth_shell.dart`) shows in place of a missing brand logo.
class OAuthLetterTile extends StatelessComponent {
  const OAuthLetterTile({super.key, required this.displayName, this.size = 20});

  final String displayName;
  final double size;

  @override
  Component build(BuildContext context) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return div(
      classes: 'z-oauth-letter-tile',
      styles: Styles(width: size.px, height: size.px, fontSize: (size * 0.5).px),
      [.text(initial)],
    );
  }
}

@css
List<StyleRule> get oauthIconStyles => [
  css('.z-oauth-mark').styles(display: .inlineFlex, alignItems: .center, justifyContent: .center),
  css('.z-oauth-icon-img').styles(radius: .all(Radius.circular(4.px)), raw: const {'object-fit': 'contain'}),
  css('.z-oauth-letter-tile').styles(
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    radius: .all(Radius.circular(6.px)),
    backgroundColor: primaryColor,
    color: onPrimaryColor,
    fontWeight: .w700,
    raw: const {'flex-shrink': '0'},
  ),
];
