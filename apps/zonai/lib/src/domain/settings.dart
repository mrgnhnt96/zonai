import 'dart:convert';

import 'package:yaml/yaml.dart';
import '../deps/args.dart';
import '../deps/fs.dart';

class Settings {
  const Settings({
    required this.migrationsPath,
    required this.schemasPath,
    required this.extensionsPath,
    required this.operationsPath,
    required this.rulesPath,
    required this.configPath,
    required this.dataPath,
    required this.emailTemplatesPath,
    required this.rateLimitPath,
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
      configPath: normalize(['lib', 'src', 'config']),
      emailTemplatesPath: normalize(['lib', 'src', 'email_templates']),
      rateLimitPath: normalize(['lib', 'src', 'rate_limit']),
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
      rateLimitPath: switch (map['rateLimitPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.rateLimitPath,
      },
      configPath: switch (map['configPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.configPath,
      },
      emailTemplatesPath: switch (map['emailTemplatesPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.emailTemplatesPath,
      },
      basePath: basePath,
    );
  }

  final String migrationsPath;
  final String dataPath;
  final String schemasPath;
  final String extensionsPath;
  final String rulesPath;
  final String rateLimitPath;
  final String operationsPath;
  final String configPath;
  final String? basePath;
  final String emailTemplatesPath;

  String _normalize(List<String> paths) {
    return fs.path.normalize(fs.path.joinAll([?basePath, ...paths]));
  }

  /// The path to the binary for the extensions
  String get compiledExtensionsPath =>
      _normalize([defaultZonaiDirectory, 'executables', 'db_extensions.exe']);
  String get compiledRulesPath =>
      _normalize([defaultZonaiDirectory, 'executables', 'db_rules.exe']);
  String get compiledOperationsPath =>
      _normalize([defaultZonaiDirectory, 'executables', 'db_operations.exe']);
  String get compiledConfigPath =>
      _normalize([defaultZonaiDirectory, 'executables', 'db_config.exe']);
  String get compiledRateLimitPath =>
      _normalize([defaultZonaiDirectory, 'executables', 'db_rate_limit.exe']);
  String get zonaiSqlitePath =>
      fs.path.normalize(fs.path.join(dataPath, 'zonai.sqlite'));
}
