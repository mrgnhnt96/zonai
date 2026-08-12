import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/target_os.dart';

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
    required this.version,
    required this.buildSettings,
    required this.cronsPath,
    required this.imagesPath,
    required this.path,
    this.host,
    this.port,
    this.basePath,
    this.dartSdkPath,
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
      path: 'zonai.yml',
      migrationsPath: normalize([defaultZonaiDirectory, 'migrations']),
      dataPath: normalize([defaultZonaiDirectory, 'data']),
      schemasPath: normalize(['lib', 'src', 'schemas']),
      extensionsPath: normalize(['lib', 'src', 'extensions']),
      rulesPath: normalize(['lib', 'src', 'rules']),
      operationsPath: normalize(['lib', 'src', 'operations']),
      configPath: normalize(['lib', 'src', 'config']),
      emailTemplatesPath: normalize(['lib', 'src', 'email_templates']),
      rateLimitPath: normalize(['lib', 'src', 'rate_limit']),
      cronsPath: normalize(['lib', 'src', 'crons']),
      imagesPath: normalize([defaultZonaiDirectory, 'data', 'images']),
      buildSettings: BuildSettings.current(),
      version: kVersion,
    );

    if (settings == null) {
      return defaultSettings;
    }

    final yaml = loadYaml(settings.readAsStringSync());
    final map = jsonDecode(jsonEncode(yaml));

    final dataPath = switch (map['dataPath']) {
      final String value => normalize([value]),
      _ => defaultSettings.dataPath,
    };

    return Settings(
      path: settings.path,
      migrationsPath: switch (map['migrationsPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.migrationsPath,
      },
      dataPath: dataPath,
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
      version: switch (map['version']) {
        final String value => value,
        _ => defaultSettings.version,
      },
      cronsPath: switch (map['cronsPath']) {
        final String value => normalize([value]),
        _ => defaultSettings.cronsPath,
      },
      imagesPath: switch (map['imagesPath']) {
        final String value => normalize([value]),
        _ => fs.path.normalize(fs.path.join(dataPath, 'images')),
      },
      buildSettings: switch (map['buildSettings']) {
        final Map<String, dynamic> value => BuildSettings.fromJson(value),
        _ => defaultSettings.buildSettings,
      },
      host: switch (map['host']) {
        final String value => value,
        _ => defaultSettings.host,
      },
      port: switch (map['port']) {
        final int value => value,
        _ => defaultSettings.port,
      },
      basePath: basePath,
      dartSdkPath: switch (map['dartSdkPath']) {
        final String value => value,
        _ => defaultSettings.dartSdkPath,
      },
    );
  }

  final String migrationsPath;
  final String dataPath;
  final String schemasPath;
  final String extensionsPath;
  final String rulesPath;
  final String rateLimitPath;
  final String cronsPath;
  final String imagesPath;
  final String operationsPath;
  final String configPath;
  final String? basePath;
  final String emailTemplatesPath;
  final String version;
  final BuildSettings buildSettings;
  final String path;
  final String? host;
  final int? port;
  final String? dartSdkPath;

  String _normalize(List<String> paths) {
    return fs.path.normalize(fs.path.joinAll([?basePath, ...paths]));
  }

  String get buildDirectory => _normalize(['build']);
  String get buildExecutableDirectory =>
      _normalize([buildDirectory, compiledExecutableDirectory]);
  String get buildExecutablePath => _normalize([
    buildDirectory,
    switch (buildSettings.targetOs) {
      .windows => 'zonai.exe',
      _ => 'zonai',
    },
  ]);
  String get buildRulesPath =>
      _normalize([buildExecutableDirectory, 'db_rules.exe']);
  String get buildOperationsPath =>
      _normalize([buildExecutableDirectory, 'db_operations.exe']);
  String get buildRulesSnapshotPath =>
      _normalize([buildExecutableDirectory, 'db_rules.aot']);
  String get buildOperationsSnapshotPath =>
      _normalize([buildExecutableDirectory, 'db_operations.aot']);
  String get buildConfigPath =>
      _normalize([buildExecutableDirectory, 'db_config.exe']);
  String get buildRateLimitPath =>
      _normalize([buildExecutableDirectory, 'db_rate_limit.exe']);
  String get buildExtensionsPath =>
      _normalize([buildExecutableDirectory, 'db_extensions.exe']);
  String get buildCronsPath =>
      _normalize([buildExecutableDirectory, 'db_crons.exe']);

  /// Where `zonai build` places the target's shared libraries, matching the
  /// `.zonai/lib` path the running binary resolves them from.
  String get buildNativeLibDirectory =>
      _normalize([buildDirectory, defaultZonaiDirectory, 'lib']);
  String get buildMigrationsPath =>
      _normalize([buildDirectory, migrationsPath]);
  String get buildSettingsPath => _normalize([buildDirectory, path]);
  String get buildEmailTemplatesPath =>
      _normalize([buildDirectory, emailTemplatesPath]);
  String get buildImagesPath => _normalize([buildDirectory, imagesPath]);

  /// The path to the binary for the extensions
  String get compiledExecutableDirectory =>
      _normalize([defaultZonaiDirectory, 'executables']);
  String get compiledExtensionsPath =>
      _normalize([compiledExecutableDirectory, 'db_extensions.exe']);
  String get compiledRulesPath =>
      _normalize([compiledExecutableDirectory, 'db_rules.exe']);
  String get compiledOperationsPath =>
      _normalize([compiledExecutableDirectory, 'db_operations.exe']);
  String get compiledRulesSnapshotPath =>
      _normalize([compiledExecutableDirectory, 'db_rules.aot']);
  String get compiledOperationsSnapshotPath =>
      _normalize([compiledExecutableDirectory, 'db_operations.aot']);
  String get compiledConfigPath =>
      _normalize([compiledExecutableDirectory, 'db_config.exe']);
  String get compiledRateLimitPath =>
      _normalize([compiledExecutableDirectory, 'db_rate_limit.exe']);
  String get compiledCronsPath =>
      _normalize([compiledExecutableDirectory, 'db_crons.exe']);

  String get pubspecLockPath => _normalize(['pubspec.lock']);

  /// The project's resolved package graph, written by `dart pub get`.
  String get packageConfigPath =>
      _normalize(['.dart_tool', 'package_config.json']);

  /// Generated Dart entry for workers (ops/rules isolate spawn under JIT).
  String get generatedOperationsEntryPath =>
      _normalize(['.dart_tool', 'zonai', 'db_operations.dart']);
  String get generatedRulesEntryPath =>
      _normalize(['.dart_tool', 'zonai', 'db_rules.dart']);
  String get generatedProjectMainPath =>
      _normalize(['.dart_tool', 'zonai', 'project_main.dart']);

  /// Where the project's package graph and zonai's own are merged, for
  /// `--packages`. See [mergePackageConfigs].
  ///
  /// Deliberately *not* at `<dir>/.dart_tool/package_config.json` for any
  /// directory: that is the shape the SDK auto-discovers by walking up from a
  /// script, and a second config it could find on its own would decide builds
  /// nobody pointed at it. This one only ever applies when passed explicitly.
  String get mergedPackageConfigPath =>
      _normalize(['.dart_tool', 'zonai', 'package_config.json']);
  String get compiledProjectBinaryPath =>
      _normalize([defaultZonaiDirectory, 'zonai']);

  String get zonaiSqlitePath =>
      fs.path.normalize(fs.path.join(dataPath, 'zonai.sqlite'));

  set version(String value) {
    final file = fs.file(path);
    if (!file.existsSync()) {
      return;
    }

    final yaml = YamlEditor(file.readAsStringSync());

    yaml.update(['version'], value);

    file.writeAsStringSync(yaml.toString());
  }
}

class BuildSettings {
  BuildSettings({required this.targetOs, required this.targetArch}) {
    if (!TargetOs.current().canCompile(targetOs, targetArch)) {
      throw Exception(
        'Cannot build for ${targetOs.name}/${targetArch.name} on '
        '${TargetOs.current().name}/${Arch.current().name}: Dart only '
        'cross-compiles to Linux; every other target must match the host.',
      );
    }
  }

  factory BuildSettings.fromJson(Map<String, dynamic> json) {
    return BuildSettings(
      targetOs: TargetOs.values.byName(json['targetOs']),
      targetArch: Arch.values.byName(json['targetArch']),
    );
  }

  static BuildSettings current() {
    return BuildSettings(
      targetOs: TargetOs.current(),
      targetArch: Arch.current(),
    );
  }

  final TargetOs targetOs;
  final Arch targetArch;

  bool targetsCurrentPlatform() {
    return targetOs == TargetOs.current() && targetArch == Arch.current();
  }

  /// The `dart compile` flags that aim an artifact at this target.
  ///
  /// A getter rather than four literals at each call site because omitting it
  /// is invisible: an artifact built for the host ships inside a target bundle
  /// and every transport it feeds has a fallback, so the build passes, the
  /// deploy passes, and what is lost is a faster path nobody was watching.
  /// `zonai build` shipped host-arch ops/rules AOT snapshots for exactly that
  /// reason -- the `.exe` compile beside them spread these flags and the
  /// snapshot compile did not.
  List<String> get compileTargetArgs => [
    '--target-os',
    targetOs.name,
    '--target-arch',
    targetArch.name,
  ];

  Map<String, dynamic> toJson() {
    return {'targetOs': targetOs.name, 'targetArch': targetArch.name};
  }

  @override
  String toString() {
    return 'BuildSettings(os: ${targetOs.name}, arch: ${targetArch.name})';
  }
}
