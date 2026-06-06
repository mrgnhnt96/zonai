import '../../../deps/fs.dart';
import '../../../deps/settings.dart';
import '../../../utils/dart_name_format.dart';
import '../../../utils/schema_names.dart';
import '../../../utils/schema_tables.dart';
import 'schema_scaffold.dart';

class CreateSchemaResult {
  const CreateSchemaResult.success({
    required this.schemaPath,
    required this.idsPath,
    required this.names,
  }) : error = null;

  const CreateSchemaResult.failure(this.error)
    : schemaPath = null,
      idsPath = null,
      names = null;

  final String? schemaPath;
  final String? idsPath;
  final SchemaNames? names;
  final String? error;

  bool get ok => schemaPath != null;
}

CreateSchemaResult createSchema({
  required String rawEntityName,
  required SchemaTableKind kind,
  SchemaAuthConfig authConfig = const SchemaAuthConfig(),
}) {
  final entityClass = formatDartClassName(rawEntityName);
  if (entityClass.isEmpty) {
    return const CreateSchemaResult.failure('Entity name is required');
  }

  if (kind == SchemaTableKind.auth && !authConfig.hasAnyAuth) {
    return const CreateSchemaResult.failure('Select at least one auth method');
  }

  final schemasDir = fs.directory(settings.schemasPath);
  schemasDir.createSync(recursive: true);

  final idsPath = fs.path.normalize(
    fs.path.join(fs.path.dirname(settings.schemasPath), 'ids.dart'),
  );
  final idsFile = fs.file(idsPath);
  final idsContent = idsFile.existsSync() ? idsFile.readAsStringSync() : '';

  final names = SchemaNames.fromEntityClass(
    entityClass,
    usedIdSuffixes: parseIdSuffixes(idsContent),
  );

  final schemaPath = fs.path.normalize(
    fs.path.join(settings.schemasPath, names.fileName),
  );
  final schemaFile = fs.file(schemaPath);

  if (schemaFile.existsSync()) {
    return CreateSchemaResult.failure('Schema already exists: $schemaPath');
  }

  final existingTables = loadSchemaTables(settings.schemasPath);
  if (existingTables.any((table) => table.tableName == names.tableName)) {
    return CreateSchemaResult.failure(
      'Table name already exists: ${names.tableName}',
    );
  }

  schemaFile.writeAsStringSync(
    scaffoldSchemaSource(names: names, kind: kind, authConfig: authConfig),
  );

  final updatedIds = _updateIdsFile(
    idsPath: idsPath,
    idsContent: idsContent,
    names: names,
  );
  if (updatedIds case final String error?) {
    schemaFile.deleteSync();
    return CreateSchemaResult.failure(error);
  }

  return CreateSchemaResult.success(
    schemaPath: schemaPath,
    idsPath: idsPath,
    names: names,
  );
}

String? _updateIdsFile({
  required String idsPath,
  required String idsContent,
  required SchemaNames names,
}) {
  final idsFile = fs.file(idsPath);
  final hasUnion = RegExp(r'sealed class Id implements').hasMatch(idsContent);

  if (idsContent.isEmpty) {
    idsFile.createSync(recursive: true);
    idsFile.writeAsStringSync(scaffoldInitialIdsFile(names).trim());
    return null;
  }

  if (idsContent.contains('class ${names.idClass}') ||
      idsContent.contains('sealed class ${names.idClass}')) {
    return 'ID type already exists: ${names.idClass}';
  }

  if (hasUnion) {
    var updated = appendUnionIdCase(idsContent, names);
    updated = '$updated${scaffoldUnionIdClass(names)}';
    idsFile.writeAsStringSync(updated);
    return null;
  }

  idsFile.writeAsStringSync('$idsContent\n${scaffoldStandaloneIdClass(names)}');
  return null;
}
