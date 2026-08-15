import 'package:jaspr/dom.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/components/theme/oauth_icon.dart';
import 'package:zonai_web/components/theme/oauth_sanitize.dart';

OAuthProviderPublic _provider({
  OAuthProviderKind kind = OAuthProviderKind.custom,
  String displayName = 'Acme SSO',
  String? iconUrl,
  String? iconSvg,
}) {
  return OAuthProviderPublic(
    id: 'acme',
    displayName: displayName,
    table: 'users',
    kind: kind,
    iconUrl: iconUrl,
    iconSvg: iconSvg,
    startPath: '/auth/oauth/start/acme?table=users',
  );
}

void main() {
  group('OAuthProviderIcon rung 1 — known kind', () {
    testComponents('renders the bundled mark for a built-in kind', (tester) async {
      tester.pumpComponent(OAuthProviderIcon(provider: _provider(kind: OAuthProviderKind.github)));

      // GitHub's bundled mark is a single <path> inside an <svg> — proves the
      // bundled asset rendered, not the letter tile or an <img>.
      expect(find.tag('svg'), findsOneComponent);
      expect(find.tag('path'), findsOneComponent);
      expect(find.tag('img'), findsNothing);
    });

    testComponents('a known kind ignores a caller-supplied iconUrl/iconSvg', (tester) async {
      tester.pumpComponent(
        OAuthProviderIcon(
          provider: _provider(
            kind: OAuthProviderKind.github,
            iconUrl: 'https://evil.example/impersonate-github.png',
            iconSvg: '<svg><path d="M0 0"/></svg>',
          ),
        ),
      );

      // Still the bundled mark — a built-in kind never defers to a
      // developer-supplied icon field. See OAuthIcon's doc comment.
      expect(find.tag('svg'), findsOneComponent);
      expect(find.tag('img'), findsNothing);
    });

    for (final kind in OAuthProviderKind.values) {
      if (kind == OAuthProviderKind.custom) continue;
      testComponents('OAuthProviderKind.${kind.name} never renders an <img> (zero network requests)', (tester) async {
        tester.pumpComponent(OAuthProviderIcon(provider: _provider(kind: kind)));

        expect(find.tag('img'), findsNothing);
        expect(find.tag('svg'), findsOneComponent);
      });
    }
  });

  group('OAuthProviderIcon rung 2 — sanitized inline iconSvg', () {
    testComponents('renders sanitized iconSvg for a custom provider', (tester) async {
      const source = '<svg viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="#123456"/></svg>';
      tester.pumpComponent(OAuthProviderIcon(provider: _provider(iconSvg: source)));

      final rawTextElements = find.byComponentPredicate((c) => c is RawText).evaluate();
      expect(rawTextElements, hasLength(1));
      final rawText = rawTextElements.single.component as RawText;
      expect(rawText.text, sanitizeInlineSvg(source));
      expect(find.tag('img'), findsNothing);
    });

    testComponents('an iconSvg that fails sanitization falls through to iconUrl', (tester) async {
      tester.pumpComponent(
        OAuthProviderIcon(
          provider: _provider(iconSvg: '<svg><script>alert(1)</script></svg>', iconUrl: 'https://example.com/icon.png'),
        ),
      );

      expect(find.byComponentPredicate((c) => c is RawText), findsNothing);
      expect(find.tag('img'), findsOneComponent);
    });

    testComponents('an iconSvg that fails sanitization with no iconUrl falls through to the letter tile', (
      tester,
    ) async {
      tester.pumpComponent(
        OAuthProviderIcon(
          provider: _provider(displayName: 'Acme SSO', iconSvg: '<svg onload="alert(1)"/>'),
        ),
      );

      expect(find.byComponentPredicate((c) => c is RawText), findsNothing);
      expect(find.tag('img'), findsNothing);
      expect(find.text('A'), findsOneComponent);
    });
  });

  group('OAuthProviderIcon rung 3 — iconUrl', () {
    testComponents('renders an <img> for a custom provider with an iconUrl', (tester) async {
      tester.pumpComponent(
        OAuthProviderIcon(
          provider: _provider(displayName: 'Acme SSO', iconUrl: 'https://example.com/icon.png'),
        ),
      );

      final imgs = find.byComponentPredicate((c) => c is img).evaluate();
      expect(imgs, hasLength(1));
      final image = imgs.single.component as img;
      expect(image.src, 'https://example.com/icon.png');
      expect(image.alt, 'Acme SSO');
    });
  });

  group('OAuthProviderIcon rung 4 — letter tile', () {
    testComponents('renders the initial-letter tile when no icon is available', (tester) async {
      tester.pumpComponent(OAuthProviderIcon(provider: _provider(displayName: 'Acme SSO')));

      expect(find.byType(OAuthLetterTile), findsOneComponent);
      expect(find.text('A'), findsOneComponent);
      expect(find.tag('svg'), findsNothing);
      expect(find.tag('img'), findsNothing);
    });

    testComponents('falls back to "?" for an empty display name', (tester) async {
      tester.pumpComponent(OAuthLetterTile(displayName: ''));

      expect(find.text('?'), findsOneComponent);
    });
  });
}
