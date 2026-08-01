// dart format width=100
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';

/// Generates `.dart_tool/zonai/project_main.dart` — a project-linked entry that
/// registers in-process ops/rules and boots the full CLI (`serve`, `db`, …).
class ProjectGenerator {
  const ProjectGenerator();

  static String get executablePath =>
      fs.path.join('.dart_tool', 'zonai', 'project_main.dart');

  Future<void> create() async {
    final outDir = fs.directory(fs.path.join('.dart_tool', 'zonai'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    final out = fs.file(executablePath);
    out.writeAsStringSync(_source());
    logger.debug('Generated project entry: ${out.path}');
  }

  String _source() {
    final b = StringBuffer();
    b.writeln("import 'package:zonai/src/bootstrap.dart';");
    b.writeln(
      "import 'package:zonai/src/db_mutator/host_worker_registries.dart';",
    );
    b.writeln("import 'db_operations.dart' as ops;");
    b.writeln("import 'db_rules.dart' as rules;");
    b.writeln();
    b.writeln('Future<void> main(List<String> args) async {');
    b.writeln('  if (!HostWorkerRegistries.forceWorkers) {');
    b.writeln(
      '    HostWorkerRegistries.operations = ops.createDbOperations();',
    );
    b.writeln('    HostWorkerRegistries.rules = rules.createDbRules();');
    b.writeln('  }');
    b.writeln('  await runZonai(args);');
    b.writeln('}');
    return b.toString();
  }
}
