// ignore_for_file: cascade_invocations

import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../lib/src/deps/args.dart';
import '../lib/src/deps/clean_up.dart';
import '../lib/src/deps/extensions.dart';
import '../lib/src/deps/fs.dart';
import '../lib/src/deps/keyboard_input.dart';
import '../lib/src/deps/kill.dart';
import '../lib/src/deps/logger.dart';
import '../lib/src/deps/migrate.dart';
import '../lib/src/deps/mutations.dart';
import '../lib/src/deps/operations.dart';
import '../lib/src/deps/process.dart';
import '../lib/src/deps/revali.dart';
import '../lib/src/deps/rules.dart';
import '../lib/src/deps/settings.dart';
import '../lib/src/deps/stdin.dart';
import '../lib/src/deps/zonai_db.dart';
import '../lib/src/utils/args.dart';
import '../lib/src/zonai_runner.dart';

void main(List<String> arguments) async {
  await _run(arguments);
}

Future<void> _run(List<String> arguments) async {
  final parsed = Args.parse(arguments);

  final log = Logger(
    level:
        Level.fromString(parsed.getOrNull('log')) ??
        switch ((parsed['quiet'], parsed['loud'])) {
          (true, _) => Level.error,
          (_, true) => Level.verbose,
          (_, _) => Level.info,
        },
  );

  log.verbose('Starting Zonai CLI');
  log.verbose('Parsed arguments: $parsed');
  log.verbose('Logger Level: ${log.level}');

  await runScoped(
    () async {
      try {
        kill; // sets up the kill handler
        exitCode = await run();
        logger.verbose('Exited with code: $exitCode');
        kill.force();
      } catch (e, stack) {
        logger.error('Error: $e', stack);
        kill.force();
        exitCode = 1;
      }
    },
    values: {
      argsProvider.overrideWith(() => parsed),
      fsProvider,
      loggerProvider.overrideWith(() => log),
      processProvider,
      cleanUpProvider,
      mutationsProvider,
      keyboardInputProvider,
      migrateProvider,
      extensionsProvider,
      rulesProvider,
      killProvider,
      stdinProvider,
      operationsProvider,
      revaliProvider,
      zonaiDbProvider,
      settingsProvider,
    },
  );
}
