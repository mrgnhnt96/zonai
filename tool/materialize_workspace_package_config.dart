// Copies the workspace root package_config.json into a member package's
// .dart_tool/ so tools (e.g. Revali) that look for a local package config
// find one on Windows as well as Unix.
//
// Run from the repository root:
//   dart run tool/materialize_workspace_package_config.dart apps/server

import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/materialize_workspace_package_config.dart <package-path> [...]',
    );
    exit(64);
  }

  final repoRoot = _repoRoot();
  final workspaceConfig = File('${repoRoot.path}/.dart_tool/package_config.json');
  if (!workspaceConfig.existsSync()) {
    stderr.writeln(
      '${workspaceConfig.path} is missing. Run `dart pub get` at the workspace root first.',
    );
    exit(1);
  }

  for (final packagePath in args) {
    final packageDir = Directory('${repoRoot.path}/${_normalizePath(packagePath)}');
    if (!packageDir.existsSync()) {
      stderr.writeln('Missing package directory: ${packageDir.path}');
      exit(1);
    }

    final dartToolDir = Directory('${packageDir.path}/.dart_tool');
    dartToolDir.createSync(recursive: true);

    final destination = File('${dartToolDir.path}/package_config.json');
    await workspaceConfig.copy(destination.path);
    stdout.writeln('Wrote ${destination.path}');
  }
}

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: zonai_workspace')) {
      return dir;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not find zonai workspace root from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/').replaceAll(RegExp(r'^\.?/+'), '');
}
