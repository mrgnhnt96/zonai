import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../constants/theme.dart';
import '../providers/theme_provider.dart';

/// Button that toggles between light and dark appearance.
///
/// Lives under [AppShell] (the client island); must not be `@client` itself.
class ThemeToggle extends StatelessComponent {
  const ThemeToggle({super.key});

  @override
  Component build(BuildContext context) {
    context.watch(themeProvider);
    final isDark = context.read(themeProvider.notifier).isDarkEffective;
    return button(
      type: .button,
      classes: 'theme-toggle',
      attributes: {
        'title': isDark ? 'Switch to light mode' : 'Switch to dark mode',
      },
      onClick: () => context.read(themeProvider.notifier).toggle(),
      [.text(isDark ? 'Light' : 'Dark')],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.theme-toggle').styles(
      padding: .symmetric(horizontal: 12.px, vertical: 8.px),
      cursor: .pointer,
      radius: .all(Radius.circular(8.px)),
      border: .all(color: borderColor, width: 1.px, style: .solid),
      fontWeight: .w600,
      fontSize: 0.8125.rem,
      color: mutedColor,
      backgroundColor: surfaceColor,
      raw: const {'font': 'inherit'},
    ),
    css('.theme-toggle:hover').styles(
      backgroundColor: hoverColor,
      color: fgColor,
    ),
  ];
}
