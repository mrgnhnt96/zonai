// dart format width=100
import 'package:file/file.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/ipc_protocol_stamp.dart';
import 'package:zonai/src/domain/operations/operation_generator.dart';
import 'package:zonai/src/domain/project/project_generator.dart';
import 'package:zonai/src/domain/rules/rule_generator.dart';
import 'package:zonai/src/domain/settings.dart';

/// Compiles the project-linked binary (in-process ops/rules + full CLI).
class ProjectBinary {
  ProjectBinary();

  Future<int> compile({BuildSettings? buildSettings}) async {
    // Ensure worker sources (and create* factories) exist.
    await OperationGenerator(
      operations: _dartFiles(settings.operationsPath),
      schemasPath: settings.schemasPath,
    ).create();
    await RuleGenerator(rules: _dartFiles(settings.rulesPath)).create();
    await const ProjectGenerator().create();

    final target = switch (buildSettings) {
      != null => settings.buildExecutablePath,
      _ => settings.compiledProjectBinaryPath,
    };
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    logger.info('Compiling project binary → $target');
    final result = await process.runDart([
      'compile',
      'exe',
      '-D__ZONAI_COMPILED__=true',
      ...env.dartDefineArgs,
      // `zonai build` always ships a production binary (no asserts). Dev
      // `.zonai/zonai` keeps asserts unless `--release` is set.
      if (buildSettings == null && !args.release) '--enable-asserts',
      if (buildSettings case final build?) ...[
        '--target-os',
        build.targetOs.name,
        '--target-arch',
        build.targetArch.name,
      ],
      ProjectGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile project binary');
      logger.info('----');
      logger.error('${result.stderr}');
      logger.error('${result.stdout}');
      return result.exitCode;
    }

    writeProtocolStamp(target);

    logger.info('Compiled project binary');
    return 0;
  }

  List<File> _dartFiles(String path) {
    final directory = fs.directory(path);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();
  }
}
