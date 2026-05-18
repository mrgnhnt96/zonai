import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../constants/theme.dart';

class HomeScreen extends StatelessComponent {
  const HomeScreen({super.key});

  @override
  Component build(BuildContext context) {
    return main_(classes: 'home', [
      div(classes: 'card', [
        h1(classes: 'title', [.text('Welcome home')]),
        p(classes: 'subtitle', [.text('You are signed in.')]),
        button(
          classes: 'sign-out',
          type: .button,
          onClick: () => context.read(authProvider.notifier).signOut(),
          [.text('Sign out')],
        ),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
        css('.home', [
          css('&').styles(
            flex: Flex(grow: 1, shrink: 0),
            display: .flex,
            alignItems: .center,
            justifyContent: .center,
            padding: .all(24.px),
          ),
          css('.card').styles(
            width: 100.percent,
            maxWidth: 480.px,
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
            margin: .only(bottom: 24.px),
            fontSize: 0.95.rem,
            color: const Color('#64748b'),
          ),
          css('.sign-out').styles(
            margin: .only(top: 8.px),
            padding: .symmetric(horizontal: 16.px, vertical: 10.px),
            cursor: .pointer,
            radius: .all(Radius.circular(8.px)),
            border: .all(color: borderColor, width: 1.px, style: .solid),
            fontWeight: .w600,
            fontSize: 0.875.rem,
            color: primaryColor,
            backgroundColor: Colors.transparent,
          ),
          css('.sign-out:hover').styles(backgroundColor: const Color('#f8fafc')),
        ]),
      ];
}
