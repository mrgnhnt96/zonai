import '../../../deps/fs.dart';
import '../../../deps/settings.dart';
import '../../../utils/dart_name_format.dart';
import '../../../utils/schema_tables.dart';
import 'part_scaffold.dart';

class CreatePartResult {
  const CreatePartResult.success(this.path) : error = null;
  const CreatePartResult.failure(this.error) : path = null;

  final String? path;
  final String? error;

  bool get ok => path != null;
}

CreatePartResult createWorkerPart({
  required WorkerPartType type,
  required String rawClassName,
  SchemaTableInfo? table,
}) {
  final className = formatDartClassName(rawClassName);
  if (className.isEmpty) {
    return const CreatePartResult.failure('Class name is required');
  }

  if (type.requiresTable) {
    if (table == null) {
      return const CreatePartResult.failure('Select a table');
    }
  }

  final outputDir = _outputDirectory(type);
  fs.directory(outputDir).createSync(recursive: true);

  final fileName = '${pascalToSnake(className)}.dart';
  final outputPath = fs.path.normalize(fs.path.join(outputDir, fileName));
  final outputFile = fs.file(outputPath);

  if (outputFile.existsSync()) {
    return CreatePartResult.failure('File already exists: $outputPath');
  }

  final schemaImportPath = table == null
      ? ''
      : _schemaImportPath(
          schemaFilePath: table.schemaFilePath,
          outputPath: outputPath,
        );

  final source = scaffoldWorkerPart(
    type: type,
    className: className,
    schemaImportPath: schemaImportPath,
    table: table,
  );

  outputFile.writeAsStringSync(source);
  return CreatePartResult.success(outputPath);
}

String _outputDirectory(WorkerPartType type) {
  return switch (type) {
    WorkerPartType.operations => settings.operationsPath,
    WorkerPartType.tableRules || WorkerPartType.rowRules => settings.rulesPath,
    WorkerPartType.extension => settings.extensionsPath,
    WorkerPartType.rateLimit => settings.rateLimitPath,
    WorkerPartType.cron => settings.cronsPath,
  };
}

String _schemaImportPath({
  required String schemaFilePath,
  required String outputPath,
}) {
  final relative = fs.path.relative(
    schemaFilePath,
    from: fs.path.dirname(outputPath),
  );
  return relative.replaceAll(r'\', '/');
}
