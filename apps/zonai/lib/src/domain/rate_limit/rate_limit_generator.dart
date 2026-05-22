import 'package:file/file.dart';
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';

class RateLimitGenerator {
  const RateLimitGenerator({required this.rateLimits});

  final List<File> rateLimits;

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'db_rate_limit.dart');

  Future<void> create() async {
    logger.debug('Starting rate limit generator');

    final dartFiles = rateLimits
        .where((f) => fs.path.extension(f.path) == '.dart')
        .toList();

    final root = fs.currentDirectory.path;
    final usedAliases = <String>{
      for (final e in InternalDbArtifacts.rateLimits) e.alias,
    };
    final entries = <({String alias, String importPath})>[
      for (final e in InternalDbArtifacts.rateLimits)
        (alias: e.alias, importPath: e.importPath),
    ];

    final outDir = fs.directory(fs.path.join('.dart_tool', 'zonai'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final outDirAbsolute = outDir.absolute.path;

    final sorted = [...dartFiles]..sort((a, b) => a.path.compareTo(b.path));
    for (final file in sorted) {
      final relativePosix = _relativePosixPath(file, root);
      final importPath = _relativePosixPath(file, outDirAbsolute);
      final alias = _uniqueAlias(relativePosix, usedAliases);
      entries.add((alias: alias, importPath: importPath));
    }

    fs.file(executablePath).writeAsStringSync(_source(entries));

    logger.debug('Generated rate limit file: $executablePath');
    logger.debug('Used ${entries.length} rate limit modules');
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

  String _source(List<({String alias, String importPath})> entries) {
    final b = StringBuffer();
    b.writeln(
      "import 'package:zonai_schema/src/handlers/rate_limits/db_rate_limits.dart' as db_rate_limits;",
    );
    b.writeln("import 'package:zonai_schema/zonai_schema.dart';");
    for (final e in entries) {
      b.writeln("import '${e.importPath}' as ${e.alias};");
    }
    b.writeln();
    b.writeln('void main() {');
    b.writeln('  db_rate_limits.DbRateLimits(');
    b.writeln('    rateLimits: [');
    for (final e in entries) {
      b.writeln(
        '      loadRateLimit(${_dartStringLiteral(e.importPath)}, ${e.alias}.main),',
      );
    }
    b.writeln('    ],');
    b.writeln('  ).start();');
    b.writeln('}');
    b.writeln();
    b.writeln(
      'RateLimits loadRateLimit(String sourcePath, RateLimits Function() load) {',
    );
    b.writeln('  Object? value;');
    b.writeln('  try {');
    b.writeln('    value = load();');
    b.writeln('  } catch (e, st) {');
    b.writeln('    Error.throwWithStackTrace(StateError(');
    b.writeln(
      "      'Failed to load rate limits from ' + sourcePath + ': "
      r'$e'
      "',",
    );
    b.writeln('    ), st);');
    b.writeln('  }');
    b.writeln('  if (value is! RateLimits) {');
    b.writeln(
      '    final got = value == null ? "null" : value.runtimeType.toString();',
    );
    b.writeln('    throw StateError(');
    b.writeln(
      "      'Rate limit file at ' + sourcePath + ' must return RateLimits from main(); got "
      r'$got'
      ".',",
    );
    b.writeln('    );');
    b.writeln('  }');
    b.writeln('  return value;');
    b.writeln('}');
    return b.toString();
  }

  static String _dartStringLiteral(String s) =>
      "'${s.replaceAll('\\', '\\\\').replaceAll("'", r"\'")}'";
}
