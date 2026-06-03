// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:zonai_web/components/theme/ui_styles.dart' as _ui_styles;
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
    _app.AppShell: ClientTarget<_app.AppShell>('app', params: __appAppShell),
  },
  styles: () => [
    ..._ui_styles.zonaiUiStyles,
    ..._theme.styles,
    ..._app.App.styles,
    ..._home_screen.HomeScreen.styles,
  ],
);

Map<String, Object?> __appAppShell(_app.AppShell c) => {
  'initialSqliteNames': c.initialSqliteNames,
  'initialDisplayNames': c.initialDisplayNames,
  'tablesLoadError': c.tablesLoadError,
  'initialSchemaShapes': c.initialSchemaShapes,
  'initialSignedIn': c.initialSignedIn,
  'initialPath': c.initialPath,
  'initialAppName': c.initialAppName,
  'initialAuthTypeNames': c.initialAuthTypeNames,
};
