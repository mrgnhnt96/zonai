// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:zonai_website/src/interactive/install_command.dart'
    deferred as _install_command;
import 'package:zonai_website/src/interactive/stream_demo.dart'
    deferred as _stream_demo;
import 'package:zonai_website/src/sections/nav.dart' deferred as _nav;

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
    'install_command': ClientLoader(
      (p) => _install_command.InstallCommand(command: p['command'] as String),
      loader: _install_command.loadLibrary,
    ),
    'stream_demo': ClientLoader(
      (p) => _stream_demo.StreamDemo(),
      loader: _stream_demo.loadLibrary,
    ),
    'nav': ClientLoader((p) => _nav.SiteNav(), loader: _nav.loadLibrary),
  },
);
