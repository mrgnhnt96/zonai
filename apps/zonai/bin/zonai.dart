// ignore_for_file: cascade_invocations

import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_logger/zonai_logger.dart';

import 'package:zonai/src/deps/config_resolver.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/extensions.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/keyboard_input.dart';
import 'package:zonai/src/deps/kill.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/migrate.dart';
import 'package:zonai/src/deps/mutations.dart';
import 'package:zonai/src/deps/operations.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/revali.dart';
import 'package:zonai/src/deps/rules.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/stdin.dart';
import 'package:zonai/src/deps/config.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai/src/zonai_runner.dart';

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
      configProvider,
      configResolverProvider,
      killProvider,
      stdinProvider,
      operationsProvider,
      revaliProvider,
      zonaiDbProvider,
      settingsProvider,
    },
  );
}
