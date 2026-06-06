import 'package:file/file.dart';
import 'package:zonai/src/internal/internal_db_artifacts.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';

class OperationGenerator {
  const OperationGenerator({
    required this.operations,
    required this.schemasPath,
  });

  final List<File> operations;
  final String schemasPath;

  static final _schemaTablePattern = RegExp(
    r"final\s+(\w+)\s*=\s*(?:authTable|table)\s*\(\s*'([^']+)'",
  );

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'db_operations.dart');

  Future<void> create() async {
    logger.debug('Starting operation generator');

    final dartOps = operations
        .where((f) => fs.path.extension(f.path) == '.dart')
        .toList();

    final root = fs.currentDirectory.path;
    final usedAliases = <String>{
      for (final e in InternalDbArtifacts.operations) e.alias,
    };
    final entries = <({String alias, String importPath})>[
      for (final e in InternalDbArtifacts.operations)
        (alias: e.alias, importPath: e.importPath),
    ];

    final outDir = fs.directory(fs.path.join('.dart_tool', 'zonai'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final outDirAbsolute = outDir.absolute.path;

    final sorted = [...dartOps]..sort((a, b) => a.path.compareTo(b.path));
    for (final file in sorted) {
      final relativePosix = _relativePosixPath(file, root);
      final importPath = _relativePosixPath(file, outDirAbsolute);
      final alias = _uniqueAlias(relativePosix, usedAliases);
      entries.add((alias: alias, importPath: importPath));
    }

    final schemaEntries = _discoverSchemas(
      root: root,
      outDirAbsolute: outDirAbsolute,
      usedAliases: usedAliases,
    );

    final out = fs.file(executablePath);
    out.writeAsStringSync(_dbOperationsDartSource(entries, schemaEntries));

    logger.debug('Generated operation file: ${out.path}');
    logger.debug('Used ${entries.length} operations');
    for (final e in entries) {
      logger.debug('  - ${e.alias}: ${e.importPath}');
    }
    logger.debug('Used ${schemaEntries.length} schema tables');
    for (final e in schemaEntries) {
      logger.debug('  - ${e.alias}.${e.getter} (${e.tableName})');
    }
  }

  List<({String alias, String importPath, String getter, String tableName})>
  _discoverSchemas({
    required String root,
    required String outDirAbsolute,
    required Set<String> usedAliases,
  }) {
    final directory = fs.directory(schemasPath);
    if (!directory.existsSync()) {
      return [];
    }

    final tables =
        <
          ({String alias, String importPath, String getter, String tableName})
        >[];

    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || fs.path.extension(entity.path) != '.dart') {
        continue;
      }

      final content = entity.readAsStringSync();
      final tableMatches = _schemaTablePattern.allMatches(content).toList();
      if (tableMatches.isEmpty) {
        continue;
      }

      final relativePosix = _relativePosixPath(entity, root);
      final importPath = _relativePosixPath(entity, outDirAbsolute);
      final alias = _uniqueAlias('schema_$relativePosix', usedAliases);

      for (final match in tableMatches) {
        final getter = match.group(1)!;
        final tableName = match.group(2)!;
        if (InternalDbArtifacts.tableNames.contains(tableName)) {
          continue;
        }

        tables.add((
          alias: alias,
          importPath: importPath,
          getter: getter,
          tableName: tableName,
        ));
      }
    }

    tables.sort((a, b) => a.tableName.compareTo(b.tableName));
    return tables;
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

  String _dbOperationsDartSource(
    List<({String alias, String importPath})> entries,
    List<({String alias, String importPath, String getter, String tableName})>
    schemaEntries,
  ) {
    final b = StringBuffer();
    b.writeln(
      "import 'package:zonai_schema/src/handlers/operations/db_operations.dart' as db_operations;",
    );
    b.writeln("import 'package:zonai_schema/zonai_schema.dart';");
    for (final e in entries) {
      b.writeln("import '${e.importPath}' as ${e.alias};");
    }

    final schemaImports = <String, String>{};
    for (final e in schemaEntries) {
      schemaImports.putIfAbsent(e.importPath, () => e.alias);
    }
    for (final entry in schemaImports.entries) {
      b.writeln("import '${entry.key}' as ${entry.value};");
    }

    b.writeln();
    b.writeln('void main() {');
    b.writeln('  db_operations.DbOperations(');
    b.writeln('    operations: [');
    for (final e in entries) {
      b.writeln(
        '      loadOperation(${_dartStringLiteral(e.importPath)}, ${e.alias}.main),',
      );
    }
    b.writeln('    ],');
    b.writeln('    tables: [');
    for (final e in schemaEntries) {
      b.writeln('      ${e.alias}.${e.getter},');
    }
    b.writeln('    ],');
    b.writeln('  ).start();');
    b.writeln('}');
    b.writeln();
    b.writeln(
      'TableOperations loadOperation('
      'String sourcePath, TableOperations Function() load) {',
    );
    b.writeln('  Object? value;');
    b.writeln('  try {');
    b.writeln('    value = load();');
    b.writeln('  } catch (e, st) {');
    b.writeln('    Error.throwWithStackTrace(StateError(');
    b.writeln(
      "      'Failed to load operations from ' + sourcePath + ': "
      r'$e'
      "',",
    );
    b.writeln('    ), st);');
    b.writeln('  }');
    b.writeln('  if (value is! TableOperations) {');
    b.writeln(
      '    final got = value == null ? "null" : value.runtimeType.toString();',
    );
    b.writeln('    throw StateError(');
    b.writeln(
      "      'Operations file at ' + sourcePath + ' must return a non-null TableOperations from main(); '",
    );
    b.writeln(
      "      'got "
      r'$got'
      ".',",
    );
    b.writeln('    );');
    b.writeln('  }');
    b.writeln('  return value;');
    b.writeln('}');
    return b.toString();
  }

  /// Single-quoted Dart string literal for use in generated source.
  static String _dartStringLiteral(String s) =>
      "'${s.replaceAll('\\', '\\\\').replaceAll("'", r"\'")}'";
}
