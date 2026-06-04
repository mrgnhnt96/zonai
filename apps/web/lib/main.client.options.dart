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
        initialPath: p['initialPath'] as String,
        initialAppName: p['initialAppName'] as String,
        initialAuthTypeNames: (p['initialAuthTypeNames'] as List<Object?>)
            .cast<String>(),
      ),
      loader: _auth_app_shell.loadLibrary,
    ),
    'home_app_shell': ClientLoader(
      (p) => _home_app_shell.HomeAppShell(
        initialSqliteNames: (p['initialSqliteNames'] as List<Object?>)
            .cast<String>(),
        initialDisplayNames: (p['initialDisplayNames'] as List<Object?>)
            .cast<String>(),
        tablesLoadError: p['tablesLoadError'] as String?,
        initialSchemaShapes: (p['initialSchemaShapes'] as Map<String, Object?>)
            .map((k, v) => MapEntry(k, (v as Map<String, Object?>))),
        initialCollectionActions:
            (p['initialCollectionActions'] as Map<String, Object?>).map(
              (k, v) => MapEntry(k, (v as Map<String, Object?>)),
            ),
        initialPath: p['initialPath'] as String,
        initialAppName: p['initialAppName'] as String,
      ),
      loader: _home_app_shell.loadLibrary,
    ),
  },
);
