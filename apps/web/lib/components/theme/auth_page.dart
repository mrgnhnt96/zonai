import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../theme_toggle.dart';
import 'ui_styles.dart';

/// Centered auth layout with theme toggle in the corner.
class AuthPage extends StatelessComponent {
  const AuthPage({super.key, required this.child});

  final Component child;

  @override
  Component build(BuildContext context) {
    return main_(classes: ZonaiClasses.authPage, [
      div(classes: ZonaiClasses.authPageTheme, [const ThemeToggle()]),
      child,
    ]);
  }
}
