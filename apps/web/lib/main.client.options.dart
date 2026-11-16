// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:zonai_web/components/auth_app_shell.dart'
    deferred as _auth_app_shell;
import 'package:zonai_web/components/home_app_shell.dart'
    deferred as _home_app_shell;

/// Default [ClientOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.client.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultClientOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ClientOptions get defaultClientOptions => ClientOptions(
  clients: {
    'auth_app_shell': ClientLoader(
      (p) => _auth_app_shell.AuthAppShell(
        initialPath: p.get<String>('initialPath'),
        initialAppName: p.get<String>('initialAppName'),
        initialBaseUrl: p.get<String>('initialBaseUrl'),
        hasBrandLogo: p.get<bool>('hasBrandLogo'),
        initialAuthTypeNames: p
            .get<List<Object?>>('initialAuthTypeNames')
            .cast<String>(),
        initialOAuthProviders: p
            .get<List<Object?>>('initialOAuthProviders')
            .cast<Map<String, Object?>>(),
      ),
      loader: _auth_app_shell.loadLibrary,
    ),
    'home_app_shell': ClientLoader(
      (p) => _home_app_shell.HomeAppShell(
        initialSqliteNames: p
            .get<List<Object?>>('initialSqliteNames')
            .cast<String>(),
        initialDisplayNames: p
            .get<List<Object?>>('initialDisplayNames')
            .cast<String>(),
        tablesLoadError: p.get<String?>('tablesLoadError'),
        initialSchemaShapes: p
            .get<Map<String, Object?>>('initialSchemaShapes')
            .cast<String, Map<String, Object?>>(),
        initialCollectionActions: p
            .get<Map<String, Object?>>('initialCollectionActions')
            .cast<String, Map<String, Object?>>(),
        initialPath: p.get<String>('initialPath'),
        initialAppName: p.get<String>('initialAppName'),
        initialBaseUrl: p.get<String>('initialBaseUrl'),
        hasBrandLogo: p.get<bool>('hasBrandLogo'),
        initialPhotosConfig: p.get<Map<String, Object?>>('initialPhotosConfig'),
      ),
      loader: _home_app_shell.loadLibrary,
    ),
  },
);
