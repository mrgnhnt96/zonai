import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/gen/client_settings.dart';
import 'package:zonai/src/domain/target_os.dart';

import '../deps/args.dart';
import '../deps/fs.dart';
import '../utils/parse_bytes.dart';

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
    this.logDatabaseMaxBytes,
    this.client,
  });

  static const defaultZonaiDirectory = '.zonai';

  /// Where `zonai gen client` records the schema it generated from.
  static const clientSchemaFileName = 'schema.json';

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
      // Opt-in, and absent means unlimited rather than "some default
      // ceiling". A cap that is reached stops log writes entirely, which
      // removes observability at exactly the moment something is going
      // wrong -- not a thing to impose on a deployment that never asked.
      //
      // An unparseable value is *not* silently ignored: falling back to
      // unlimited would leave an operator believing they had a ceiling they
      // do not have, which is the failure this whole feature exists to
      // prevent one instance of.
      logDatabaseMaxBytes: switch (map['logDatabaseMaxSize']) {
        null => null,
        final int value when value > 0 => value,
        final String value =>
          parseBytes(value) ??
              (throw FormatException(
                'Invalid logDatabaseMaxSize: "$value". Expected a positive '
                'byte count, optionally with a b/kb/mb/gb/tb suffix '
                '(e.g. 512mb).',
              )),
        final value => throw FormatException(
          'Invalid logDatabaseMaxSize: $value. Expected a size like 512mb.',
        ),
      },
      // Absent means "no typed client for this project", which is the state
      // every existing project is in -- so this is null rather than a default
      // block, and `zonai gen client` is what reports on it.
      client: switch (map['client']) {
        null => null,
        final Map<String, dynamic> value => ClientSettings.fromJson(
          value,
          normalize: normalize,
        ),
        final value => throw FormatException(
          'Invalid client: $value. Expected a map (see `zonai gen client '
          '--help`).',
        ),
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

  /// Hard ceiling on the log database file, in bytes, or `null` for no cap.
  ///
  /// Set with `logDatabaseMaxSize` in `zonai.yaml`. Off by default: reaching
  /// it makes log writes fail, and a deployment that did not ask for that
  /// would lose its logs at the worst possible moment. It exists for people
  /// who want a guarantee that this one table can never be what fills a
  /// volume.
  ///
  /// Only expressible because `_log` has a file of its own —
  /// `max_page_count` bounds a *file*, so on the shared database the ceiling
  /// would be hit by whichever write arrived first, application inserts
  /// included.
  final int? logDatabaseMaxBytes;

  /// The `client:` block, or `null` when `zonai.yaml` has none.
  ///
  /// `zonai gen client` is the only reader; every other command ignores it.
  final ClientSettings? client;

  /// `.zonai/schema.json` — the generator's entire input, and the artifact
  /// `--check` compares a hash against.
  String get clientSchemaPath =>
      _normalize([defaultZonaiDirectory, clientSchemaFileName]);

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

  /// The `_log` table's own database file, attached onto both connections as
  /// `logdb` (see `kLogDbSchema`).
  ///
  /// Logs are disposable in a way application data is not -- high churn,
  /// bounded retention, nothing worth reconstructing -- and a separate file
  /// is what makes that difference actionable: `unlink` becomes a recovery
  /// option, `VACUUM` takes its exclusive lock on log data instead of on the
  /// application's tables, and `PRAGMA max_page_count` becomes usable at all
  /// (it bounds a *file*, so on a shared database the ceiling is hit by
  /// whichever write arrives first, application inserts included).
  ///
  /// Motivating case, 2026-08-13: `_log` reached 4.6M rows and filled a 1GB
  /// production volume, and every recovery path zonai ships needed a write
  /// the full disk was denying.
  String get zonaiLogSqlitePath =>
      fs.path.normalize(fs.path.join(dataPath, 'zonai_log.sqlite'));

  /// The `_rate_limit` table's own database file, attached as `ratedb` (see
  /// `kRateLimitDbSchema`).
  ///
  /// Disposable for the same reasons as the log database, plus one of its
  /// own: this table is written on every request that reaches a limited
  /// operation, so leaving it in the shared file puts per-request churn into
  /// the application database's WAL, competing with writes that actually
  /// matter.
  String get zonaiRateLimitSqlitePath =>
      fs.path.normalize(fs.path.join(dataPath, 'zonai_rate_limit.sqlite'));

  /// Every SQLite file zonai owns, application database first.
  ///
  /// Anything that deletes, copies or measures "the database" needs all of
  /// them; a list is how a future split stays automatically covered instead
  /// of being remembered at each call site.
  List<String> get zonaiSqlitePaths => [
    zonaiSqlitePath,
    zonaiLogSqlitePath,
    zonaiRateLimitSqlitePath,
  ];

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
