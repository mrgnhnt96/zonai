import 'package:file/file.dart';

import '../../deps/fs.dart';
import '../../deps/logger.dart';

class ConfigGenerator {
  const ConfigGenerator(this.file);

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'db_config.dart');

  final String file;

  Future<void> create() async {
    logger.debug('Starting config generator');

    final configFile = fs.file(file);
    if (fs.path.extension(configFile.path) != '.dart') return;

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
    b.writeln(
      "import 'package:zonai_schema/src/handlers/config/db_config.dart' as db_config;",
    );
    b.writeln("import 'package:zonai_schema/zonai_schema.dart';");
    b.writeln("import '${entry.importPath}' as ${entry.alias};");
    b.writeln();
    b.writeln('void main() {');
    b.writeln('  final resolved = appConfig(${entry.alias}.main);');
    b.writeln('  if (resolved == null) {');
    b.writeln(
      "    throw StateError('Config main() must return a non-null AppConfig');",
    );
    b.writeln('  }');
    b.writeln('  db_config.DbConfig(config: resolved).start();');
    b.writeln('}');
    b.writeln();
    b.writeln('AppConfig? appConfig(AppConfig appConfig()) {');
    b.writeln('  try {');
    b.writeln('    return switch (appConfig()) {');
    b.writeln('      final AppConfig c => c,');
    b.writeln('      _ => null,');
    b.writeln('    };');
    b.writeln('  } catch (e) {');
    b.writeln('    return null;');
    b.writeln('  }');
    b.writeln('}');
    return b.toString();
  }
}
