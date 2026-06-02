// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:zonai_web/app.dart' deferred as _app;

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
    'app': ClientLoader(
      (p) => _app.AppShell(
        initialSqliteNames: (p['initialSqliteNames'] as List<Object?>)
            .cast<String>(),
        initialDisplayNames: (p['initialDisplayNames'] as List<Object?>)
            .cast<String>(),
        tablesLoadError: p['tablesLoadError'] as String?,
        initialSchemaShapes: (p['initialSchemaShapes'] as Map<String, Object?>)
            .map((k, v) => MapEntry(k, (v as Map<String, Object?>))),
        initialSignedIn: p['initialSignedIn'] as bool,
        initialPath: p['initialPath'] as String,
        initialAppName: p['initialAppName'] as String,
        initialAuthTypeNames: (p['initialAuthTypeNames'] as List<Object?>)
            .cast<String>(),
      ),
      loader: _app.loadLibrary,
    ),
  },
);
