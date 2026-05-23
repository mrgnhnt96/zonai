// Generates lib/src/internal/internal_db_artifacts.dart from framework files.
//
// Run from this package:
//   dart run tool/generate_internal_db_artifacts.dart
//
// Pass --check to exit 1 when the file is out of date (for CI).

import 'dart:io';

const _generatedHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Built-in operations and rules for framework-managed SQLite tables.
//
// These are merged into generated `db_operations` / `db_rules` /
// `db_rate_limit` executables; app authors do not add files for them under
// `lib/src/operations`, `lib/src/rules`, or `lib/src/rate_limit`.
//
// Regenerate: dart run tool/generate_internal_db_artifacts.dart
''';

final _tableNamePattern = RegExp(r"collection\s*\(\s*'([^']+)'");
final _collectionGetterPattern = RegExp(r'final\s+(\w+)\s*=\s*collection\s*\(');

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final packageRoot = Directory.current;
  final libRoot = Directory('${packageRoot.path}/lib/src/internal');
  if (!libRoot.existsSync()) {
    stderr.writeln(
      'Run from the zonai package root (lib/src/internal not found).',
    );
    exit(1);
  }

  final operations = _discoverEntries(
    Directory('${libRoot.path}/operations'),
    suffix: '_operations.dart',
    importPrefix: 'package:zonai/src/internal/operations/',
  );
  final rules = _discoverEntries(
    Directory('${libRoot.path}/rules'),
    suffix: '_rules.dart',
    importPrefix: 'package:zonai/src/internal/rules/',
    exclude: {'internal_rules.dart'},
  );
  final rateLimits = _discoverEntries(
    Directory('${libRoot.path}/rate_limits'),
    suffix: '_rate_limits.dart',
    importPrefix: 'package:zonai/src/internal/rate_limits/',
  );
  final collections = _discoverCollections(libRoot);

  final output = _formatDart(
    operations: operations,
    rules: rules,
    rateLimits: rateLimits,
    collections: collections,
  );
  final outFile = File('${libRoot.path}/internal_db_artifacts.dart');

  if (checkOnly) {
    final existing = outFile.existsSync() ? outFile.readAsStringSync() : '';
    if (existing != output) {
      stderr.writeln(
        '${outFile.path} is out of date. Run: dart run tool/generate_internal_db_artifacts.dart',
      );
      exit(1);
    }
    stdout.writeln('${outFile.path} is up to date.');
    return;
  }

  outFile.writeAsStringSync(output);
  stdout.writeln('Wrote ${outFile.path}');
  stdout.writeln(
    '  ${operations.length} operations, ${rules.length} rules, '
    '${rateLimits.length} rate limits, ${collections.length} collections',
  );
  stdout.writeln('collections:');
  for (final c in collections) {
    stdout.writeln('  - ${c.tableName}');
  }
  stdout.writeln('operations:');
  for (final o in operations) {
    stdout.writeln('  - ${o.alias}');
  }
  stdout.writeln('rules:');
  for (final r in rules) {
    stdout.writeln('  - ${r.alias}');
  }
  stdout.writeln('rate limits:');
  for (final r in rateLimits) {
    stdout.writeln('  - ${r.alias}');
  }
}

List<({String importPath, String alias})> _discoverEntries(
  Directory dir, {
  required String suffix,
  required String importPrefix,
  Set<String> exclude = const {},
}) {
  if (!dir.existsSync()) {
    return [];
  }

  final entries = <({String importPath, String alias})>[];
  for (final entity in dir.listSync().whereType<File>()) {
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith(suffix) || exclude.contains(name)) {
      continue;
    }
    final stem = name.substring(0, name.length - '.dart'.length);
    entries.add((
      importPath: '$importPrefix$name',
      alias: 'zonai_internal_$stem',
    ));
  }
  entries.sort((a, b) => a.importPath.compareTo(b.importPath));
  return entries;
}

List<({String importPath, String getter, String tableName})>
_discoverCollections(Directory internalRoot) {
  final collections =
      <({String importPath, String getter, String tableName})>[];
  for (final entity in internalRoot.listSync()) {
    if (entity is! File) {
      continue;
    }
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith('_collection.dart')) {
      continue;
    }
    final content = entity.readAsStringSync();
    final tableMatch = _tableNamePattern.firstMatch(content);
    final getterMatch = _collectionGetterPattern.firstMatch(content);
    if (tableMatch == null || getterMatch == null) {
      stderr.writeln(
        'Skipping $name: expected `final <getter> = collection(\'<table>\', ...)`',
      );
      continue;
    }
    collections.add((
      importPath: 'package:zonai/src/internal/$name',
      getter: getterMatch.group(1)!,
      tableName: tableMatch.group(1)!,
    ));
  }
  collections.sort((a, b) => a.tableName.compareTo(b.tableName));
  return collections;
}

String _formatDart({
  required List<({String importPath, String alias})> operations,
  required List<({String importPath, String alias})> rules,
  required List<({String importPath, String alias})> rateLimits,
  required List<({String importPath, String getter, String tableName})>
  collections,
}) {
  final buffer = StringBuffer()..writeln('$_generatedHeader');
  buffer.writeln();
  buffer.writeln("import 'package:raindrop/raindrop.dart' show Schema;");
  for (final c in collections) {
    buffer.writeln("import '${c.importPath}' as _schema_${c.getter};");
  }
  buffer.writeln();
  buffer.writeln('abstract final class InternalDbArtifacts {');
  buffer.writeln(
    '  static const operations = <({String importPath, String alias})>[',
  );
  for (final e in operations) {
    buffer.writeln('    (');
    buffer.writeln('      importPath:');
    buffer.writeln("          '${e.importPath}',");
    buffer.writeln("      alias: '${e.alias}',");
    buffer.writeln('    ),');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  static const rules = <({String importPath, String alias})>[',
  );
  for (final e in rules) {
    buffer.writeln('    (');
    buffer.writeln('      importPath:');
    buffer.writeln("          '${e.importPath}',");
    buffer.writeln("      alias: '${e.alias}',");
    buffer.writeln('    ),');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  static const rateLimits = <({String importPath, String alias})>[',
  );
  for (final e in rateLimits) {
    buffer.writeln('    (');
    buffer.writeln('      importPath:');
    buffer.writeln("          '${e.importPath}',");
    buffer.writeln("      alias: '${e.alias}',");
    buffer.writeln('    ),');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  /// Framework-managed collections (import path, top-level getter, table).',
  );
  buffer.writeln(
    '  static const collections = <({String importPath, String getter, String tableName})>[',
  );
  for (final c in collections) {
    buffer.writeln('    (');
    buffer.writeln('      importPath:');
    buffer.writeln("          '${c.importPath}',");
    buffer.writeln("      getter: '${c.getter}',");
    buffer.writeln("      tableName: '${c.tableName}',");
    buffer.writeln('    ),');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln('  /// Collection schemas synced to SQLite on database open.');
  buffer.writeln('  static final schemas = <Schema<Object?>>[');
  for (final c in collections) {
    buffer.writeln('    _schema_${c.getter}.${c.getter},');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  /// SQLite table names managed by the framework (not user schemas).',
  );
  final tableLiteral = collections.map((c) => "'${c.tableName}'").join(', ');
  buffer.writeln('  static const tableNames = {$tableLiteral};');
  buffer.writeln('}');
  buffer.writeln();
  return buffer.toString();
}
