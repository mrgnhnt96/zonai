// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:zonai_web/components/home_screen.dart' as _home_screen;
import 'package:zonai_web/components/sign_in_screen.dart' as _sign_in_screen;
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
  clients: {_app.AppShell: ClientTarget<_app.AppShell>('app')},
  styles: () => [
    ..._theme.styles,
    ..._app.App.styles,
    ..._home_screen.HomeScreen.styles,
    ..._sign_in_screen.SignInScreen.styles,
  ],
);
