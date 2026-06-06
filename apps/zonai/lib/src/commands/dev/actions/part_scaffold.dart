import '../../../utils/dart_name_format.dart';
import '../../../utils/schema_tables.dart';

enum WorkerPartType {
  operations,
  tableRules,
  rowRules,
  extension,
  rateLimit,
  cron,
}

extension WorkerPartTypeLabels on WorkerPartType {
  String get label => switch (this) {
    WorkerPartType.operations => 'Operations',
    WorkerPartType.tableRules => 'Table rules',
    WorkerPartType.rowRules => 'Row rules',
    WorkerPartType.extension => 'Extension',
    WorkerPartType.rateLimit => 'Rate limit',
    WorkerPartType.cron => 'Cron job',
  };

  bool get requiresTable => this != WorkerPartType.cron;
}

String defaultClassName(WorkerPartType type, SchemaTableInfo table) {
  return switch (type) {
    WorkerPartType.operations => '${table.entityClass}Operations',
    WorkerPartType.tableRules => '${table.entityClass}TableRules',
    WorkerPartType.rowRules => '${table.entityClass}RowRules',
    WorkerPartType.extension => '${table.entityClass}Extensions',
    WorkerPartType.rateLimit => '${table.entityClass}RateLimits',
    WorkerPartType.cron => 'MyCron',
  };
}

String scaffoldWorkerPart({
  required WorkerPartType type,
  required String className,
  required String schemaImportPath,
  SchemaTableInfo? table,
}) {
  return switch (type) {
    WorkerPartType.operations => _scaffoldOperations(
      className: className,
      schemaImportPath: schemaImportPath,
      table: table!,
    ),
    WorkerPartType.tableRules => _scaffoldTableRules(
      className: className,
      schemaImportPath: schemaImportPath,
      table: table!,
    ),
    WorkerPartType.rowRules => _scaffoldRowRules(
      className: className,
      schemaImportPath: schemaImportPath,
      table: table!,
    ),
    WorkerPartType.extension => _scaffoldExtension(
      className: className,
      schemaImportPath: schemaImportPath,
      table: table!,
    ),
    WorkerPartType.rateLimit => _scaffoldRateLimit(
      className: className,
      schemaImportPath: schemaImportPath,
      table: table!,
    ),
    WorkerPartType.cron => _scaffoldCron(className: className),
  };
}

String _scaffoldOperations({
  required String className,
  required String schemaImportPath,
  required SchemaTableInfo table,
}) {
  final authMixin = table.isAuthTable ? ' with AuthOperations' : '';

  return '''
import '$schemaImportPath';
import 'package:zonai_schema/zonai_schema.dart';

final class $className extends TableOperations<${table.tableClass}, ${table.entityClass}>$authMixin {
  $className() : super(${table.getter});
}

$className main() => $className();
''';
}

String _scaffoldTableRules({
  required String className,
  required String schemaImportPath,
  required SchemaTableInfo table,
}) {
  if (table.isAuthTable) {
    return '''
import '$schemaImportPath';
import 'package:zonai_schema/zonai_schema.dart';

$className main() => $className();

final class $className extends AuthTableRules<${table.tableClass}, ${table.entityClass}> {
  $className() : super(${table.getter});
}
''';
  }

  return '''
import '$schemaImportPath';
import 'package:zonai_schema/zonai_schema.dart';

$className main() => $className();

final class $className extends TableRules<${table.tableClass}, ${table.entityClass}> {
  $className() : super(${table.getter});

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
''';
}

String _scaffoldRowRules({
  required String className,
  required String schemaImportPath,
  required SchemaTableInfo table,
}) {
  if (table.isAuthTable) {
    return '''
import '$schemaImportPath';
import 'package:zonai_schema/zonai_schema.dart';

$className main() => $className();

class $className extends AuthRowRules<${table.tableClass}, ${table.entityClass}> {
  $className() : super(${table.getter});
}
''';
  }

  return '''
import '$schemaImportPath';
import 'package:zonai_schema/zonai_schema.dart';

$className main() => $className();

class $className extends RowRules<${table.tableClass}, ${table.entityClass}> {
  $className() : super(${table.getter});
}
''';
}

String _scaffoldExtension({
  required String className,
  required String schemaImportPath,
  required SchemaTableInfo table,
}) {
  return '''
import '$schemaImportPath';
import 'package:zonai_schema/zonai_schema.dart';

$className main() => $className();

class $className extends Extension<${table.entityClass}> {
  $className() : super(${table.getter});
}
''';
}

String _scaffoldRateLimit({
  required String className,
  required String schemaImportPath,
  required SchemaTableInfo table,
}) {
  final baseClass = table.isAuthTable
      ? 'AuthTableRateLimits<${table.tableClass}, ${table.entityClass}>'
      : 'TableRateLimits<${table.tableClass}, ${table.entityClass}>';

  return '''
import '$schemaImportPath';
import 'package:zonai_schema/src/rate_limits/table/rate_limits.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

$className main() => $className();

final class $className extends $baseClass {
  $className() : super(${table.getter});
}
''';
}

String _scaffoldCron({required String className}) {
  final cronName = cronNameFromClassName(className);

  return '''
import 'package:zonai_schema/zonai_schema.dart';

final class $className extends CronJob {
  $className()
    : super(
        name: '$cronName',
        schedule: Schedule.parse('0 * * * *'),
      );

  @override
  Future<void> run() async {
    // TODO: implement
  }
}

$className main() => $className();
''';
}
