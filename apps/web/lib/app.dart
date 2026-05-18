import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'components/sign_in_screen.dart';

/// Root widget mounted into `<body>` by [runApp].
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'app-root', [const SignInScreen()]);
  }

  @css
  static List<StyleRule> get styles => [css('.app-root').styles(minHeight: 100.vh, display: .flex)];
}
