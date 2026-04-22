// ignore_for_file: cascade_invocations

import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/deps/args.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/extensions.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/kill.dart';
import 'package:zonai_cli/src/deps/migrate.dart';
import 'package:zonai_cli/src/deps/operations.dart';
import 'package:zonai_cli/src/deps/process.dart';
import 'package:zonai_cli/src/deps/revali.dart';
import 'package:zonai_cli/src/deps/rules.dart';
import 'package:zonai_cli/src/deps/stdin.dart';
import 'package:zonai_cli/src/utils/args.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/zonai_runner.dart';
import 'package:zonai_logger/zonai_logger.dart';

void main(List<String> arguments) async {
  await _run(arguments);
}

Future<void> _run(List<String> arguments) async {
  final parsed = Args.parse(arguments);

  final log = Logger(
    level: switch ((parsed['quiet'], parsed['loud'])) {
      (true, _) => Level.error,
      (_, true) => Level.verbose,
      (_, _) => Level.info,
    },
  );

  log.debug('Starting Zonai CLI');
  log.debug('Parsed arguments: $parsed');
  log.debug('Logger Level: ${log.level}');

  await runScoped(
    () async {
      try {
        kill; // sets up the kill handler
        exitCode = await run();
        logger.debug('Exited with code: $exitCode');
        kill.force();
      } catch (e) {
        logger.error('Error: $e');
        exitCode = 1;
      }
    },
    values: {
      argsProvider.overrideWith(() => parsed),
      fsProvider,
      loggerProvider.overrideWith(() => log),
      processProvider,
      cleanUpProvider,
      keyboardInputProvider,
      migrateProvider,
      extensionsProvider,
      rulesProvider,
      killProvider,
      stdinProvider,
      operationsProvider,
      revaliProvider,
    },
  );
}
