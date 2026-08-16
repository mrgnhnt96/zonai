import 'package:file/file.dart';

import '../../deps/args.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';

class ConfigGenerator {
  const ConfigGenerator({required this.configs});

  final List<File> configs;

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'db_config.dart');

  Future<void> create() async {
    logger.debug('Starting config generator');

    final dartConfigs = configs
        .where((f) => fs.path.extension(f.path) == '.dart')
        .toList();
    if (dartConfigs.isEmpty) return;

    final configFile = _resolveConfigFile(dartConfigs);
    if (configFile == null) return;

    final root = fs.currentDirectory.path;
    final outDir = fs.directory(fs.path.join('.dart_tool', 'zonai'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final outDirAbsolute = outDir.absolute.path;

    final relativePosix = _relativePosixPath(configFile, root);
    final importPath = _relativePosixPath(configFile, outDirAbsolute);
    final alias = _uniqueAlias(relativePosix, {});

    final out = fs.file(executablePath);
    out.writeAsStringSync(
      _dbConfigDartSource((alias: alias, importPath: importPath)),
    );

    logger.debug('Generated config file: ${out.path}');
    logger.debug('  - $alias: $importPath');
  }

  File? _resolveConfigFile(List<File> files) {
    final sorted = [...files]..sort((a, b) => a.path.compareTo(b.path));

    if (sorted.length == 1) {
      return sorted.first;
    }

    final flavor = args.getOrNull<String>('flavor');
    if (flavor == null) {
      logger.error('Missing `flavor` argument, run with `--flavor <flavor>`');
      return null;
    }

    final matches = [
      for (final file in sorted)
        if (_flavorFor(file) == flavor) file,
    ];

    if (matches.isEmpty) {
      logger.error('No config file found for flavor "$flavor"');
      return null;
    }

    if (matches.length > 1) {
      logger.error(
        'Multiple config files match flavor "$flavor": '
        '${matches.map((f) => f.path).join(', ')}',
      );
      return null;
    }

    return matches.first;
  }

  /// Flavor from `dev.dart` or trailing segment of `db_config.dev.dart`.
  String _flavorFor(File file) {
    final stem = fs.path.basenameWithoutExtension(file.path);
    final dot = stem.lastIndexOf('.');
    return dot == -1 ? stem : stem.substring(dot + 1);
  }

  String _relativePosixPath(File file, String root) {
    var relative = fs.path.relative(file.absolute.path, from: root);
    relative = fs.path.normalize(relative);
    return relative.replaceAll(r'\', '/');
  }

  String _uniqueAlias(String relativePosix, Set<String> used) {
    final segments = switch (fs.path.split(relativePosix)) {
      ['lib', ...final rest] => rest,
      final segments => segments,
    };
    final fileStem = fs.path.basenameWithoutExtension(segments.last);
    var candidate = fileStem;
    if (used.contains(candidate)) {
      final parents = segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('_')
          : '';
      candidate = parents.isEmpty ? '${fileStem}_2' : '${parents}_$fileStem';
    }
    var n = 2;
    while (used.contains(candidate)) {
      candidate = '${fileStem}_$n';
      n++;
    }
    used.add(candidate);
    return candidate;
  }

  String _dbConfigDartSource(({String alias, String importPath}) entry) {
    final b = StringBuffer();
    b.writeln("import 'dart:io' show Platform;");
    b.writeln();
    b.writeln(
      "import 'package:zonai_schema/src/handlers/config/db_config.dart' as db_config;",
    );
    b.writeln("import 'package:zonai_schema/zonai_schema.dart';");
    b.writeln("import '${entry.importPath}' as ${entry.alias};");
    b.writeln();
    b.writeln('void main() {');
    b.writeln(
      '  db_config.DbConfig('
      'config: loadAppConfig(${_dartStringLiteral(entry.importPath)}, '
      '${entry.alias}.main),'
      ').start();',
    );
    b.writeln('}');
    b.writeln();
    b.writeln(
      'AppConfig loadAppConfig(String sourcePath, AppConfig Function() load) {',
    );
    b.writeln('  Object? value;');
    b.writeln('  try {');
    b.writeln('    value = load();');
    b.writeln('  } catch (e, st) {');
    b.writeln('    Error.throwWithStackTrace(StateError(');
    b.writeln(
      "      'Failed to load config from ' + sourcePath + ': "
      r'$e'
      "',",
    );
    b.writeln('    ), st);');
    b.writeln('  }');
    b.writeln('  if (value is! AppConfig) {');
    b.writeln(
      '    final got = value == null ? "null" : value.runtimeType.toString();',
    );
    b.writeln('    throw StateError(');
    b.writeln(
      "      'Config file at ' + sourcePath + ' must return a non-null AppConfig from main(); '",
    );
    b.writeln(
      "      'got "
      r'$got'
      ".',",
    );
    b.writeln('    );');
    b.writeln('  }');
    // The process environment wins over the compile-time `-D` define, so a
    // deployment can ship a binary with no secret baked into it at all. See
    // `AppConfig.withSecretsFromEnvironment`. Applied before `validate()` so
    // the strength check runs against the secret actually in use.
    b.writeln(
      '  final config = value.withSecretsFromEnvironment(Platform.environment);',
    );
    b.writeln('  config.validate();');
    b.writeln('  return config;');
    b.writeln('}');
    return b.toString();
  }

  /// Single-quoted Dart string literal for use in generated source.
  static String _dartStringLiteral(String s) =>
      "'${s.replaceAll('\\', '\\\\').replaceAll("'", r"\'")}'";
}
