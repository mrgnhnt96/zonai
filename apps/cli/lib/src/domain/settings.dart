import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/fs.dart';

class Settings {
  const Settings({
    required this.migrationsPath,
    required this.schemasPath,
    required this.extensionsPath,
    required this.operationsPath,
    required this.rulesPath,
    required this.dataPath,
    this.basePath,
  });

  static const defaultZonaiDirectory = '.zonai';

  factory Settings.load([String? basePath]) {
    final settings = switch ((
      fs.file(fs.path.joinAll([?basePath, 'zonai.yml'])),
      fs.file(fs.path.joinAll([?basePath, 'zonai.yaml'])),
    )) {
      (final file, _) when file.existsSync() => file,
      (_, final file) when file.existsSync() => file,
      (_, _) => switch (args.getOrNull<String>('config', abbr: 'c')) {
        final String value => fs.file(value),
        _ => null,
      },
    };

    String normalize(List<String> paths) {
      return fs.path.normalize(fs.path.joinAll([?basePath, ...paths]));
    }

    final defaultSettings = Settings(
      migrationsPath: normalize([defaultZonaiDirectory, 'migrations']),
      dataPath: normalize([defaultZonaiDirectory, 'data']),
      schemasPath: normalize(['lib', 'src', 'schemas']),
      extensionsPath: normalize(['lib', 'src', 'extensions']),
      rulesPath: normalize(['lib', 'src', 'rules']),
      operationsPath: normalize(['lib', 'src', 'operations']),
    );

    if (settings == null) {
      return defaultSettings;
    }

    final yaml = loadYaml(settings.readAsStringSync());
    final map = jsonDecode(jsonEncode(yaml));

    return Settings(
      migrationsPath: switch (map['migrationsPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.migrationsPath,
      },
      dataPath: switch (map['dataPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.dataPath,
      },
      schemasPath: switch (map['schemasPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.schemasPath,
      },
      extensionsPath: switch (map['extensionsPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.extensionsPath,
      },
      rulesPath: switch (map['rulesPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.rulesPath,
      },
      operationsPath: switch (map['operationsPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.operationsPath,
      },
      basePath: basePath,
    );
  }

  final String migrationsPath;
  final String dataPath;
  final String schemasPath;
  final String extensionsPath;
  final String rulesPath;
  final String operationsPath;
  final String? basePath;

  String _normalize(List<String> paths) {
    return fs.path.normalize(fs.path.joinAll([?basePath, ...paths]));
  }

  /// The path to the binary for the extensions
  String get compiledExtensionsPath =>
      _normalize([defaultZonaiDirectory, 'extensions', 'db_extensions.exe']);
  String get compiledRulesPath =>
      _normalize([defaultZonaiDirectory, 'rules', 'db_rules.exe']);
  String get compiledOperationsPath =>
      _normalize([defaultZonaiDirectory, 'operations', 'db_operations.exe']);
}
