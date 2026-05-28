import 'package:file/file.dart';
import 'package:zonai/src/internal/internal_db_artifacts.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';

class CronGenerator {
  const CronGenerator({required this.crons});

  final List<File> crons;

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'db_crons.dart');

  Future<void> create() async {
    logger.debug('Starting cron generator');

    final dartFiles = crons
        .where((f) => fs.path.extension(f.path) == '.dart')
        .toList();

    final root = fs.currentDirectory.path;
    final usedAliases = <String>{
      for (final e in InternalDbArtifacts.crons) e.alias,
    };
    final entries = <({String alias, String importPath})>[
      for (final e in InternalDbArtifacts.crons)
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

    logger.debug('Generated cron file: $executablePath');
    logger.debug('Used ${entries.length} cron modules');
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
      "import 'package:zonai_schema/src/handlers/cron/db_crons.dart' as db_crons;",
    );
    b.writeln("import 'package:zonai_schema/zonai_schema.dart';");
    for (final e in entries) {
      b.writeln("import '${e.importPath}' as ${e.alias};");
    }
    b.writeln();
    b.writeln('void main() {');
    b.writeln('  db_crons.DbCrons(');
    b.writeln('    jobs: [');
    for (final e in entries) {
      b.writeln(
        '      loadCronJob(${_dartStringLiteral(e.importPath)}, ${e.alias}.main),',
      );
    }
    b.writeln('    ],');
    b.writeln('  ).start();');
    b.writeln('}');
    b.writeln();
    b.writeln(
      'CronJob loadCronJob(String sourcePath, CronJob Function() load) {',
    );
    b.writeln('  Object? value;');
    b.writeln('  try {');
    b.writeln('    value = load();');
    b.writeln('  } catch (e, st) {');
    b.writeln('    Error.throwWithStackTrace(StateError(');
    b.writeln(
      "      'Failed to load cron job from ' + sourcePath + ': "
      r'$e'
      "',",
    );
    b.writeln('    ), st);');
    b.writeln('  }');
    b.writeln('  if (value is! CronJob) {');
    b.writeln(
      '    final got = value == null ? "null" : value.runtimeType.toString();',
    );
    b.writeln('    throw StateError(');
    b.writeln(
      "      'Cron file at ' + sourcePath + ' must return CronJob from main(); got "
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
