import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../providers/theme_provider.dart';
import 'theme/zonai_button.dart';

/// Button that toggles between light and dark appearance.
///
/// Lives under [AppShell] (the client island); must not be `@client` itself.
class ThemeToggle extends StatelessComponent {
  const ThemeToggle({super.key});

  @override
  Component build(BuildContext context) {
    context.watch(themeProvider);
    final isDark = context.read(themeProvider.notifier).isDarkEffective;
    return ZonaiButton(
      variant: ZonaiButtonVariant.ghost,
      attributes: {
        'title': isDark ? 'Switch to light mode' : 'Switch to dark mode',
      },
      onClick: () => context.read(themeProvider.notifier).toggle(),
      child: .text(isDark ? '☀ Light' : '☾ Dark'),
    );
  }
}
