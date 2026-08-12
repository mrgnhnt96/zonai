// dart format width=100
import 'package:file/file.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/ipc_protocol_stamp.dart';
import 'package:zonai/src/domain/message_contract_stamp.dart';
import 'package:zonai/src/domain/operations/operation_generator.dart';
import 'package:zonai/src/domain/project/project_generator.dart';
import 'package:zonai/src/domain/project/project_link.dart';
import 'package:zonai/src/domain/rules/rule_generator.dart';
import 'package:zonai/src/domain/settings.dart';

/// Compiles the project-linked binary (in-process ops/rules + full CLI).
class ProjectBinary {
  ProjectBinary();

  /// Compiles `.dart_tool/zonai/project_main.dart` into a binary.
  ///
  /// [link] is how the entry resolves `package:zonai`; pass the one the caller
  /// already decided on, so the compile and the decision to attempt it cannot
  /// disagree. Resolved here when omitted, which is only the dev host rebuild
  /// in `compile.dart`.
  Future<int> compile({BuildSettings? buildSettings, ProjectLink? link}) async {
    // Ensure worker sources (and create* factories) exist. Unconditional, and
    // ahead of the link check: these are the sources the Mailman/isolate path
    // spawns, so they are needed whether or not anything links.
    await OperationGenerator(
      operations: _dartFiles(settings.operationsPath),
      schemasPath: settings.schemasPath,
    ).create();
    await RuleGenerator(rules: _dartFiles(settings.rulesPath)).create();
    await const ProjectGenerator().create();

    final resolved = link ?? resolveProjectLink();
    if (resolved.skipReason case final reason?) {
      // Only reachable when the caller did not decide for itself; both flows
      // that do check first and bundle the published binary instead.
      logger.error('Cannot compile a project-linked binary: $reason');
      return 1;
    }

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
      // Absent for a project that depends on zonai directly: its own
      // resolution is already correct, and passing a config would only be a
      // chance to get it wrong.
      if (resolved.packageConfigPath case final packages?) '--packages=$packages',
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
    writeMessageContractStamp(target);

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
