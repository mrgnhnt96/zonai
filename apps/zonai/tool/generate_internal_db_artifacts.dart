// Generates libs/zonai_schema/lib/src/internal/internal_db_artifacts.dart.
//
// Run from this package:
//   dart run tool/generate_internal_db_artifacts.dart
//
// Generate a new internal-table migration (after editing *_table.dart):
//   dart run tool/generate_internal_db_artifacts.dart --migrate --name <description>
//
// Resync internal_db_migrations.dart from committed .sql files:
//   dart run tool/generate_internal_db_artifacts.dart --sync-migrations-dart
//
// Pass --check to exit 1 when generated files are out of date (for CI).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:raindrop_cli/src/cli/cli_runner.dart';
import 'package:zonai/gen/version.dart';

const _generatedHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Built-in operations and rules for framework-managed SQLite tables.
//
// These are merged into generated `db_operations` / `db_rules` /
// `db_rate_limit` / `db_extensions` / `db_crons` executables; app authors do not add files
// for them under `lib/src/operations`, `lib/src/rules`, `lib/src/rate_limit`,
// `lib/src/extensions`, or `lib/src/crons`.
//
// Regenerate: dart run tool/generate_internal_db_artifacts.dart
''';

const _migrationsDartHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Embedded internal-table migrations applied at runtime via [InternalDbMigrate].
//
// Regenerate SQL: dart run tool/generate_internal_db_artifacts.dart --migrate -n <name>
// Resync this file: dart run tool/generate_internal_db_artifacts.dart --sync-migrations-dart
''';

const _raindropConfig = 'raindrop.yaml';
const _migrationsDir = 'lib/src/internal/migrations';
const _migrationsDartPath = 'lib/src/internal/internal_db_migrations.dart';
const _schemaPackageRoot = '../../libs/zonai_schema';
const _schemaInternalRoot = 'lib/src/internal';
const _artifactsDartPath =
    '$_schemaPackageRoot/$_schemaInternalRoot/internal_db_artifacts.dart';
const _importPrefix = 'package:zonai_schema/src/internal';

final _tableNamePattern = RegExp(r"table\s*\(\s*'([^']+)'");
final _tableGetterPattern = RegExp(r'final\s+(\w+)\s*=\s*table\s*\(');

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final syncMigrationsDart = args.contains('--sync-migrations-dart');
  final generateMigration = args.contains('--migrate');
  final migrationName =
      _readOption(args, '--name') ??
      '_zonai_v${kVersion.replaceAll('.', '-')}__';

  final packageRoot = Directory.current;
  final schemaRoot = Directory(p.join(packageRoot.path, _schemaPackageRoot));
  final libRoot = Directory(p.join(schemaRoot.path, _schemaInternalRoot));
  if (!libRoot.existsSync()) {
    stderr.writeln(
      'Run from the zonai package root ($_schemaPackageRoot/$_schemaInternalRoot not found).',
    );
    exit(1);
  }

  if (generateMigration) {
    final exitCode = await _runRaindropGenerate(migrationName);
    if (exitCode != 0) {
      exit(exitCode);
    }
    _postProcessMigrationSqlFiles(packageRoot);
    _writeMigrationsDartFile(packageRoot);
  } else if (syncMigrationsDart) {
    _writeMigrationsDartFile(packageRoot);
  }

  final operations = _discoverEntries(
    Directory('${libRoot.path}/operations'),
    suffix: '_operations.dart',
    importPrefix: '$_importPrefix/operations/',
  );
  final rules = _discoverEntries(
    Directory('${libRoot.path}/rules'),
    suffix: '_rules.dart',
    importPrefix: '$_importPrefix/rules/',
    exclude: {'internal_rules.dart'},
  );
  final rateLimits = _discoverEntries(
    Directory('${libRoot.path}/rate_limits'),
    suffix: '_rate_limits.dart',
    importPrefix: '$_importPrefix/rate_limits/',
  );
  final extensions = _discoverEntries(
    Directory('${libRoot.path}/extensions'),
    suffix: '_extension.dart',
    importPrefix: '$_importPrefix/extensions/',
  );
  final crons = _discoverEntries(
    Directory('${libRoot.path}/crons'),
    suffix: '_cron.dart',
    importPrefix: '$_importPrefix/crons/',
  );
  final tables = _discoverTables(libRoot);

  _validateTableArtifacts(
    tables: tables,
    operationsDir: Directory('${libRoot.path}/operations'),
    rulesDir: Directory('${libRoot.path}/rules'),
  );

  final output = _formatArtifactsDart(
    operations: operations,
    rules: rules,
    rateLimits: rateLimits,
    extensions: extensions,
    crons: crons,
    tables: tables,
  );
  final outFile = File(p.join(packageRoot.path, _artifactsDartPath));

  if (checkOnly) {
    final migrationsDart = File('${packageRoot.path}/$_migrationsDartPath');
    final existingArtifacts = outFile.existsSync()
        ? outFile.readAsStringSync()
        : '';
    final existingMigrations = migrationsDart.existsSync()
        ? migrationsDart.readAsStringSync()
        : '';
    final expectedMigrations = _formatMigrationsDart(
      _loadMigrationEntries(packageRoot),
    );

    if (existingArtifacts != output ||
        existingMigrations != expectedMigrations) {
      stderr.writeln(
        'Generated internal DB files are out of date. Run: '
        'dart run tool/generate_internal_db_artifacts.dart',
      );
      if (existingArtifacts != output) {
        stderr.writeln('  - ${outFile.path}');
      }
      if (existingMigrations != expectedMigrations) {
        stderr.writeln('  - ${migrationsDart.path}');
      }
      exit(1);
    }
    stdout.writeln('Internal DB generated files are up to date.');
    return;
  }

  outFile.writeAsStringSync(output);
  stdout.writeln('Wrote ${outFile.path}');
  stdout.writeln(
    '  ${operations.length} operations, ${rules.length} rules, '
    '${rateLimits.length} rate limits, ${extensions.length} extensions, '
    '${crons.length} crons, '
    '${tables.length} tables',
  );
  stdout.writeln('tables:');
  for (final c in tables) {
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
  stdout.writeln('extensions:');
  for (final e in extensions) {
    stdout.writeln('  - ${e.alias}');
  }
  stdout.writeln('crons:');
  for (final c in crons) {
    stdout.writeln('  - ${c.alias}');
  }

  if (generateMigration || syncMigrationsDart) {
    stdout.writeln('Wrote ${packageRoot.path}/$_migrationsDartPath');
  }
}

String? _readOption(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

Future<int> _runRaindropGenerate(String migrationName) async {
  return CliRunner().run([
    '--config',
    _raindropConfig,
    'generate',
    '--name',
    migrationName,
  ]);
}

void _postProcessMigrationSqlFiles(Directory packageRoot) {
  final migrationsRoot = Directory(p.join(packageRoot.path, _migrationsDir));
  if (!migrationsRoot.existsSync()) {
    return;
  }

  for (final entity in migrationsRoot.listSync()) {
    if (entity is! File || !entity.path.endsWith('.sql')) {
      continue;
    }
    final sql = entity.readAsStringSync();
    final updated = _ensureCreateIfNotExists(sql);
    if (updated != sql) {
      entity.writeAsStringSync(updated);
      stdout.writeln('Post-processed ${entity.path} (IF NOT EXISTS)');
    }
  }
}

String _ensureCreateIfNotExists(String sql) {
  return sql
      .replaceAll(
        'CREATE UNIQUE INDEX "',
        'CREATE UNIQUE INDEX IF NOT EXISTS "',
      )
      .replaceAll('CREATE INDEX "', 'CREATE INDEX IF NOT EXISTS "')
      .replaceAll('CREATE TABLE "', 'CREATE TABLE IF NOT EXISTS "');
}

List<({String tag, String sql})> _loadMigrationEntries(Directory packageRoot) {
  final journalFile = File(
    p.join(packageRoot.path, _migrationsDir, 'meta', '_journal.json'),
  );
  if (!journalFile.existsSync()) {
    return const [];
  }

  final journal =
      jsonDecode(journalFile.readAsStringSync()) as Map<String, dynamic>;
  final entries = journal['entries'] as List<dynamic>? ?? const [];
  final migrations = <({String tag, String sql})>[];

  for (final raw in entries) {
    final entry = raw as Map<String, dynamic>;
    final tag = entry['tag'] as String;
    final sqlFile = File(p.join(packageRoot.path, _migrationsDir, '$tag.sql'));
    if (!sqlFile.existsSync()) {
      throw StateError('Missing migration SQL for tag "$tag": ${sqlFile.path}');
    }
    migrations.add((tag: tag, sql: sqlFile.readAsStringSync().trim()));
  }

  return migrations;
}

void _writeMigrationsDartFile(Directory packageRoot) {
  final output = _formatMigrationsDart(_loadMigrationEntries(packageRoot));
  final outFile = File(p.join(packageRoot.path, _migrationsDartPath));
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(output);
}

String _formatMigrationsDart(List<({String tag, String sql})> migrations) {
  final buffer = StringBuffer()..writeln('$_migrationsDartHeader');
  buffer
    ..writeln()
    ..writeln("import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';")
    ..writeln()
    ..writeln(
      '/// Versioned SQL for framework-managed SQLite tables (`0000_internal_*`, …).',
    )
    ..writeln('final internalDbMigrations = [');

  for (final migration in migrations) {
    final escapedSql = migration.sql.replaceAll("'''", r"\'''");
    buffer
      ..writeln("  const Migration('${migration.tag}', '''")
      ..write(escapedSql)
      ..writeln("'''),");
  }

  buffer.writeln('];');
  buffer.writeln();
  return buffer.toString();
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

List<({String importPath, String getter, String tableName})> _discoverTables(
  Directory internalRoot,
) {
  final tables = <({String importPath, String getter, String tableName})>[];

  void scanDir(Directory dir, String importPrefix) {
    if (!dir.existsSync()) {
      return;
    }
    for (final entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('_table.dart')) {
        continue;
      }
      final content = entity.readAsStringSync();
      final tableMatch = _tableNamePattern.firstMatch(content);
      final getterMatch = _tableGetterPattern.firstMatch(content);
      if (tableMatch == null || getterMatch == null) {
        stderr.writeln(
          'Skipping $name: expected `final <getter> = table(\'<table>\', ...)`',
        );
        continue;
      }
      tables.add((
        importPath: '$importPrefix$name',
        getter: getterMatch.group(1)!,
        tableName: tableMatch.group(1)!,
      ));
    }
  }

  scanDir(
    Directory('${internalRoot.path}/tables'),
    '$_importPrefix/tables/',
  );
  scanDir(internalRoot, '$_importPrefix/');

  tables.sort((a, b) => a.tableName.compareTo(b.tableName));
  return tables;
}

void _validateTableArtifacts({
  required List<({String importPath, String getter, String tableName})> tables,
  required Directory operationsDir,
  required Directory rulesDir,
}) {
  final errors = <String>[];

  for (final table in tables) {
    if (!_artifactImportsTable(
      operationsDir,
      tableImport: table.importPath,
      suffix: '_operations.dart',
    )) {
      errors.add(
        'Missing operations for "${table.tableName}" '
        '(expected zonai_schema lib/src/internal/operations/*_operations.dart '
        'importing ${table.importPath})',
      );
    }

    if (!_artifactImportsTable(
      rulesDir,
      tableImport: table.importPath,
      suffix: '_row_rules.dart',
    )) {
      errors.add(
        'Missing row rules for "${table.tableName}" '
        '(expected zonai_schema lib/src/internal/rules/*_row_rules.dart '
        'importing ${table.importPath})',
      );
    }

    if (!_artifactImportsTable(
      rulesDir,
      tableImport: table.importPath,
      suffix: '_table_rules.dart',
    )) {
      errors.add(
        'Missing table rules for "${table.tableName}" '
        '(expected zonai_schema lib/src/internal/rules/*_table_rules.dart '
        'importing ${table.importPath})',
      );
    }
  }

  if (errors.isEmpty) {
    return;
  }

  stderr.writeln('Internal table artifact validation failed:');
  for (final error in errors) {
    stderr.writeln('  - $error');
  }
  exit(1);
}

bool _artifactImportsTable(
  Directory dir, {
  required String tableImport,
  required String suffix,
}) {
  if (!dir.existsSync()) {
    return false;
  }

  final importPattern = RegExp(
    "import\\s+['\"]${RegExp.escape(tableImport)}['\"]",
  );

  for (final entity in dir.listSync().whereType<File>()) {
    final name = entity.uri.pathSegments.last;
    if (!name.endsWith(suffix)) {
      continue;
    }

    if (importPattern.hasMatch(entity.readAsStringSync())) {
      return true;
    }
  }

  return false;
}

String _formatArtifactsDart({
  required List<({String importPath, String alias})> operations,
  required List<({String importPath, String alias})> rules,
  required List<({String importPath, String alias})> rateLimits,
  required List<({String importPath, String alias})> extensions,
  required List<({String importPath, String alias})> crons,
  required List<({String importPath, String getter, String tableName})> tables,
}) {
  final buffer = StringBuffer()..writeln('$_generatedHeader');
  buffer.writeln();
  buffer.writeln(
    "import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' show Schema;",
  );
  for (final c in tables) {
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
    '  static const extensions = <({String importPath, String alias})>[',
  );
  for (final e in extensions) {
    buffer.writeln('    (');
    buffer.writeln('      importPath:');
    buffer.writeln("          '${e.importPath}',");
    buffer.writeln("      alias: '${e.alias}',");
    buffer.writeln('    ),');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  static const crons = <({String importPath, String alias})>[',
  );
  for (final e in crons) {
    buffer.writeln('    (');
    buffer.writeln('      importPath:');
    buffer.writeln("          '${e.importPath}',");
    buffer.writeln("      alias: '${e.alias}',");
    buffer.writeln('    ),');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  /// Framework-managed tables (import path, top-level getter, table).',
  );
  buffer.writeln(
    '  static const tables = <({String importPath, String getter, String tableName})>[',
  );
  for (final c in tables) {
    buffer.writeln('    (');
    buffer.writeln('      importPath:');
    buffer.writeln("          '${c.importPath}',");
    buffer.writeln("      getter: '${c.getter}',");
    buffer.writeln("      tableName: '${c.tableName}',");
    buffer.writeln('    ),');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  /// Table schemas ensured on database open (migrations apply changes).',
  );
  buffer.writeln('  static final schemas = <Schema<Object?>>[');
  for (final c in tables) {
    buffer.writeln('    _schema_${c.getter}.${c.getter},');
  }
  buffer.writeln('  ];');
  buffer.writeln();
  buffer.writeln(
    '  /// SQLite table names managed by the framework (not user schemas).',
  );
  final tableLiteral = tables.map((c) => "'${c.tableName}'").join(', ');
  buffer.writeln('  static const tableNames = {$tableLiteral};');
  buffer.writeln('}');
  buffer.writeln();
  return buffer.toString();
}
