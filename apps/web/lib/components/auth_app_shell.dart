import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'app_shell_overrides.dart';
import 'app_tooltip_overlay.dart';
import 'page_title_head.dart';
import '../router/auth_router.dart';

/// Client island for sign-in and other unauthenticated flows.
@client
class AuthAppShell extends StatelessComponent {
  const AuthAppShell({
    super.key,
    required this.initialPath,
    required this.initialAppName,
    required this.initialAuthTypeNames,
  });

  final String initialPath;
  final String initialAppName;
  final List<String> initialAuthTypeNames;

  @override
  Component build(BuildContext context) {
    final initialAuthTypes = [for (final name in initialAuthTypeNames) AuthType.values.byName(name)];
    return ProviderScope(
      overrides: appShellOverrides(
        initialSignedIn: false,
        initialPath: initialPath,
        initialAppName: initialAppName,
        initialAuthTypes: initialAuthTypes,
      ),
      child: Component.fragment([const PageTitleHead(), AuthRouter(initialPath: initialPath), const AppTooltipOverlay()]),
    );
  }

  @css
  static List<StyleRule> get styles => AppTooltipOverlay.styles;
}
