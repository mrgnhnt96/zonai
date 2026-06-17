import 'dart:io';

import 'package:raindrop_cli/src/core/dart_executable.dart';

import '../deps/settings.dart';

String get _projectRoot => settings.basePath ?? Directory.current.path;

/// Configures and resolves the Dart SDK executable for zonai subprocesses.
Future<String> resolveDartExecutable() async {
  DartExecutable.configuredPath = settings.dartSdkPath;
  return DartExecutable.resolve(projectRoot: _projectRoot);
}

/// Applies [settings.dartSdkPath] before invoking raindrop_cli (migrations).
void configureRaindropDartSdk() {
  DartExecutable.configuredPath = settings.dartSdkPath;
}
