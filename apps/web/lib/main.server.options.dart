// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:zonai_web/components/theme/ui_styles.dart' as _ui_styles;
import 'package:zonai_web/components/auth_app_shell.dart' as _auth_app_shell;
import 'package:zonai_web/components/home_app_shell.dart' as _home_app_shell;
import 'package:zonai_web/components/home_screen.dart' as _home_screen;
import 'package:zonai_web/constants/theme.dart' as _theme;
import 'package:zonai_web/app.dart' as _app;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _auth_app_shell.AuthAppShell: ClientTarget<_auth_app_shell.AuthAppShell>(
      'auth_app_shell',
      params: __auth_app_shellAuthAppShell,
    ),
    _home_app_shell.HomeAppShell: ClientTarget<_home_app_shell.HomeAppShell>(
      'home_app_shell',
      params: __home_app_shellHomeAppShell,
    ),
  },
  styles: () => [
    ..._ui_styles.zonaiUiStyles,
    ..._theme.styles,
    ..._app.App.styles,
    ..._home_screen.HomeScreen.styles,
  ],
);

Map<String, Object?> __auth_app_shellAuthAppShell(
  _auth_app_shell.AuthAppShell c,
) => {
  'initialPath': c.initialPath,
  'initialAppName': c.initialAppName,
  'initialAuthTypeNames': c.initialAuthTypeNames,
};
Map<String, Object?> __home_app_shellHomeAppShell(
  _home_app_shell.HomeAppShell c,
) => {
  'initialSqliteNames': c.initialSqliteNames,
  'initialDisplayNames': c.initialDisplayNames,
  'tablesLoadError': c.tablesLoadError,
  'initialSchemaShapes': c.initialSchemaShapes,
  'initialPath': c.initialPath,
  'initialAppName': c.initialAppName,
};
