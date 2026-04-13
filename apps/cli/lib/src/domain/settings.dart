import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:zonai_cli/src/deps/fs.dart';

class Settings {
  const Settings({
    required this.migrationsPath,
    required this.schemasPath,
    required this.extensionsPath,
    required this.rulesPath,
  });

  factory Settings.load() {
    final settings = switch ((fs.file('zonai.yml'), fs.file('zonai.yaml'))) {
      (final file, _) when file.existsSync() => file,
      (_, final file) when file.existsSync() => file,
      (_, _) => null,
    };

    final defaultSettings = Settings(
      migrationsPath: fs.path.join('zonai', 'migrations'),
      schemasPath: fs.path.join('lib', 'src', 'schemas'),
      extensionsPath: fs.path.join('lib', 'src', 'extensions'),
      rulesPath: fs.path.join('lib', 'src', 'rules'),
    );

    if (settings == null) {
      return defaultSettings;
    }

    final yaml = loadYaml(settings.readAsStringSync());
    final map = jsonDecode(jsonEncode(yaml));

    return Settings(
      migrationsPath: switch (map['migrationsPath']) {
        final String value => value,
        _ => defaultSettings.migrationsPath,
      },
      schemasPath: switch (map['schemasPath']) {
        final String value => value,
        _ => defaultSettings.schemasPath,
      },
      extensionsPath: switch (map['extensionsPath']) {
        final String value => value,
        _ => defaultSettings.extensionsPath,
      },
      rulesPath: switch (map['rulesPath']) {
        final String value => value,
        _ => defaultSettings.rulesPath,
      },
    );
  }

  final String migrationsPath;
  final String schemasPath;
  final String extensionsPath;
  final String rulesPath;

  String get compiledExtensionsPath => fs.path.join('zonai', 'extensions');
  String get compiledRulesPath => fs.path.join('zonai', 'rules');
}
