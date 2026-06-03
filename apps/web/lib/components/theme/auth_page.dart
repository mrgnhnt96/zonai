import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../theme_toggle.dart';
import 'auth_shell.dart';
import 'ui_styles.dart';

/// Centered auth layout with theme toggle in the corner.
class AuthPage extends StatelessComponent {
  const AuthPage({
    super.key,
    required this.child,
    this.tagline = 'Sign in to your workspace',
  });

  final Component child;
  final String tagline;

  @override
  Component build(BuildContext context) {
    return main_(classes: ZonaiClasses.authPage, [
      div(classes: ZonaiClasses.authPageBack, [const AuthBackIfNeeded()]),
      div(classes: ZonaiClasses.authPageTheme, [const ThemeToggle()]),
      AuthShell(tagline: tagline, children: [child]),
    ]);
  }
}
