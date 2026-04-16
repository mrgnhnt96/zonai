import 'package:file/file.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/logger.dart';

class ExtensionGenerator {
  const ExtensionGenerator({required this.extensions});

  final List<File> extensions;

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'db_extensions.dart');

  Future<void> create() async {
    logger.debug('Starting extension generator');

    final root = fs.currentDirectory.path;
    final usedAliases = <String>{};
    final entries = <({String alias, String importPath})>[];

    final outDir = fs.directory(fs.path.join('.dart_tool', 'zonai'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final outDirAbsolute = outDir.absolute.path;

    final sorted = [...extensions]..sort((a, b) => a.path.compareTo(b.path));
    for (final file in sorted) {
      final relativePosix = _relativePosixPath(file, root);
      final importPath = _relativePosixPath(file, outDirAbsolute);
      final alias = _uniqueAlias(relativePosix, usedAliases);
      entries.add((alias: alias, importPath: importPath));
    }

    final out = fs.file(executablePath);
    out.writeAsStringSync(_dbExtenderDartSource(entries));

    logger.debug('Generated extension file: ${out.path}');
    logger.debug('Used ${entries.length} extensions');
    for (final e in entries) {
      logger.debug('  - ${e.alias}: ${e.importPath}');
    }
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

  String _dbExtenderDartSource(
    List<({String alias, String importPath})> entries,
  ) {
    final b = StringBuffer();
    b.writeln(
      "import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart' as db_extensions;",
    );
    b.writeln("import 'package:zonai_schema/zonai_schema.dart';");
    for (final e in entries) {
      b.writeln("import '${e.importPath}' as ${e.alias};");
    }
    b.writeln();
    b.writeln('void main() {');
    b.writeln('  db_extensions.DbExtensions(');
    b.writeln('    extensions: [');
    for (final e in entries) {
      b.writeln('      ?extension(${e.alias}.main),');
    }
    b.writeln('    ],');
    b.writeln('  ).start();');
    b.writeln('}');
    b.writeln();
    b.writeln('Extension? extension(Extension ext()) {');
    b.writeln('  try {');
    b.writeln('    return switch (ext()) {');
    b.writeln('      final Extension ext => ext,');
    b.writeln('      _ => null,');
    b.writeln('    };');
    b.writeln('  } catch (e) {');
    b.writeln('    return null;');
    b.writeln('  }');
    b.writeln('}');
    return b.toString();
  }
}
