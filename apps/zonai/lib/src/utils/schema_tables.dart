import 'package:file/file.dart';

import '../deps/fs.dart';
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';

/// A user-defined table discovered from schema source files.
class SchemaTableInfo {
  const SchemaTableInfo({
    required this.tableName,
    required this.getter,
    required this.entityClass,
    required this.tableClass,
    required this.isAuthTable,
    required this.schemaFilePath,
  });

  final String tableName;
  final String getter;
  final String entityClass;
  final String tableClass;
  final bool isAuthTable;
  final String schemaFilePath;

  @override
  String toString() => tableName;
}

final _tableDefPattern = RegExp(
  r"final\s+(\w+)\s*=\s*(authTable|table)\s*\(\s*'([^']+)'\s*,\s*(\w+)\.new\s*\)",
);

final _tableClassPattern = RegExp(
  r'(?:final\s+)?class\s+(\w+Table)\s+extends\s+(AuthTable|Table)<(\w+)>',
);

/// Scans [schemasPath] for user-defined tables declared with `table(...)` or
/// `authTable(...)`.
List<SchemaTableInfo> loadSchemaTables(String schemasPath) {
  final directory = fs.directory(schemasPath);
  if (!directory.existsSync()) {
    return const [];
  }

  final tables = <SchemaTableInfo>[];

  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || fs.path.extension(entity.path) != '.dart') {
      continue;
    }

    final content = entity.readAsStringSync();
    final classInfo = _parseTableClasses(content);
    if (classInfo.isEmpty) continue;

    for (final match in _tableDefPattern.allMatches(content)) {
      final getter = match.group(1)!;
      final isAuthTable = match.group(2) == 'authTable';
      final tableName = match.group(3)!;
      final tableClass = match.group(4)!;

      if (InternalDbArtifacts.tableNames.contains(tableName)) {
        continue;
      }

      final info = classInfo[tableClass];
      if (info == null) continue;

      tables.add(
        SchemaTableInfo(
          tableName: tableName,
          getter: getter,
          entityClass: info.entityClass,
          tableClass: tableClass,
          isAuthTable: isAuthTable,
          schemaFilePath: entity.path,
        ),
      );
    }
  }

  tables.sort((a, b) => a.tableName.compareTo(b.tableName));
  return tables;
}

Map<String, ({String entityClass, bool isAuthTable})> _parseTableClasses(
  String content,
) {
  final classes = <String, ({String entityClass, bool isAuthTable})>{};

  for (final match in _tableClassPattern.allMatches(content)) {
    classes[match.group(1)!] = (
      entityClass: match.group(3)!,
      isAuthTable: match.group(2) == 'AuthTable',
    );
  }

  return classes;
}
