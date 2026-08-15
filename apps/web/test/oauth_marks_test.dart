import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/components/theme/oauth_marks.dart';

/// Structural checks on the bundled brand marks — this is the "assertion,
/// not an eyeball" proof for light/dark handling: [Color.currentColor] is
/// what makes a mark follow the ambient theme color (see the doc comment at
/// the top of `oauth_marks.dart`), so asserting *which* marks use it and
/// which never do is a direct, non-visual test of the invert/don't-invert
/// split the leaf brief calls for.
void main() {
  group('googleOAuthMark', () {
    test('is the official 4-color G, never currentColor', () {
      final fills = _pathFills(googleOAuthMark());
      expect(fills, ['#4285F4', '#34A853', '#FBBC04', '#E94235']);
      expect(fills, isNot(contains(Color.currentColor.value)));
    });
  });

  group('monochrome marks invert via currentColor', () {
    test('apple uses a single currentColor path', () {
      expect(_pathFills(appleOAuthMark()), [Color.currentColor.value]);
    });

    test('github uses a single currentColor path', () {
      expect(_pathFills(githubOAuthMark()), [Color.currentColor.value]);
    });
  });

  group('fixed-color marks never use currentColor', () {
    test('microsoft is 4 fixed-color squares', () {
      final fills = _rectFills(microsoftOAuthMark());
      expect(fills, ['#F25022', '#00A4EF', '#7FBA00', '#FFB900']);
      expect(fills, isNot(contains(Color.currentColor.value)));
    });

    test('facebook is a fixed blue circle with a white f', () {
      final fills = _pathFills(facebookOAuthMark());
      expect(fills, ['#1877F2', '#FFFFFF']);
    });

    test('discord is a single fixed-blurple path', () {
      expect(_pathFills(discordOAuthMark()), ['#5865F2']);
    });

    test('gitlab is three fixed shades of orange', () {
      expect(_pathFills(gitlabOAuthMark()), ['#E24329', '#FC6D26', '#FCA326', '#FC6D26']);
    });

    test('linkedin is a single fixed-blue path', () {
      expect(_pathFills(linkedinOAuthMark()), ['#0A66C2']);
    });
  });

  group('oauthBrandMark', () {
    for (final kind in OAuthProviderKind.values) {
      if (kind == OAuthProviderKind.custom) continue;
      test('resolves a mark for OAuthProviderKind.${kind.name}', () {
        expect(() => oauthBrandMark(kind, size: 20), returnsNormally);
      });
    }

    test('has no bundled mark for OAuthProviderKind.custom', () {
      expect(() => oauthBrandMark(OAuthProviderKind.custom, size: 20), throwsArgumentError);
    });
  });
}

List<String?> _pathFills(Component markContainer) {
  final children = (markContainer as svg).children;
  return [for (final child in children) (child as path).fill?.value];
}

List<String?> _rectFills(Component markContainer) {
  final children = (markContainer as svg).children;
  return [for (final child in children) (child as rect).fill?.value];
}
