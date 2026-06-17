import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

File _packageConfigFile() {
  final configPath = Platform.packageConfig;
  if (configPath == null) {
    throw StateError('Platform.packageConfig is null');
  }

  return File(
    configPath.startsWith('file://')
        ? Uri.parse(configPath).toFilePath()
        : configPath,
  );
}

/// Raindrop package roots resolved from the active package config.
class RaindropPackageRoots {
  RaindropPackageRoots({
    required this.raindrop,
    required this.raindropSqlite,
    required this.resqlite,
  });

  final String raindrop;
  final String raindropSqlite;
  final String resqlite;

  static RaindropPackageRoots fromPackageConfig() {
    final configFile = _packageConfigFile();
    final configDir = p.dirname(p.normalize(configFile.absolute.path));
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

    String rootFor(String packageName) {
      for (final raw in config['packages'] as List<dynamic>) {
        final pkg = raw as Map<String, dynamic>;
        if (pkg['name'] != packageName) {
          continue;
        }

        final rootUri = pkg['rootUri'] as String;
        if (rootUri.startsWith('file://')) {
          return p.normalize(Uri.parse(rootUri).toFilePath());
        }
        return p.normalize(p.join(configDir, rootUri));
      }

      throw StateError(
        'Package "$packageName" not found in ${configFile.path}',
      );
    }

    return RaindropPackageRoots(
      raindrop: rootFor('raindrop'),
      raindropSqlite: rootFor('raindrop_sqlite'),
      resqlite: rootFor('resqlite'),
    );
  }
}

String zonaiPackageRootFromConfig() {
  final configFile = _packageConfigFile();
  final configDir = p.dirname(p.normalize(configFile.absolute.path));
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

  for (final raw in config['packages'] as List<dynamic>) {
    final pkg = raw as Map<String, dynamic>;
    if (pkg['name'] != 'zonai') {
      continue;
    }

    final rootUri = pkg['rootUri'] as String;
    if (rootUri.startsWith('file://')) {
      return p.normalize(Uri.parse(rootUri).toFilePath());
    }
    return p.normalize(p.join(configDir, rootUri));
  }

  throw StateError('Package "zonai" not found in ${configFile.path}');
}
