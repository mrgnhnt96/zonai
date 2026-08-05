// dart format width=100
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/courier.dart';
import 'package:zonai/src/deps/config_resolver.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/extensions.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/keyboard_input.dart';
import 'package:zonai/src/deps/kill.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/migrate.dart';
import 'package:zonai/src/deps/mutations.dart';
import 'package:zonai/src/deps/operations.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/raindrop_sync.dart';
import 'package:zonai/src/deps/revali.dart';
import 'package:zonai/src/deps/schema_version_check.dart';
import 'package:zonai/src/deps/rate_limiter.dart';
import 'package:zonai/src/deps/rate_limits.dart';
import 'package:zonai/src/deps/crons.dart';
import 'package:zonai/src/deps/rules.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/stdin.dart';
import 'package:zonai/src/deps/config.dart';
import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/deps/versions.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai/src/zonai_runner.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// Shared CLI/server bootstrap used by `bin/zonai.dart` and generated
/// project binaries.
Future<void> runZonai(List<String> arguments) async {
  final parsed = Args.parse(arguments);

  final log = Logger(
    level:
        .fromString(parsed.getOrNull('log')) ??
        switch ((parsed['quiet'], parsed['loud'])) {
          (true, _) => .error,
          (_, true) => .verbose,
          (_, _) => .info,
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
        logger.error('Crash!', e, stack);
        kill.force();
        exitCode = 1;
      }
    },
    values: {
      argsProvider.overrideWith(() => parsed),
      fsProvider,
      courierProvider,
      envProvider,
      loggerProvider.overrideWith(() => log),
      processProvider,
      cleanUpProvider,
      mutationsProvider,
      keyboardInputProvider,
      migrateProvider,
      extensionsProvider,
      executableStopProvider,
      rulesProvider,
      rateLimitsProvider,
      cronsProvider,
      rateLimiterProvider,
      configProvider,
      configResolverProvider,
      killProvider,
      stdinProvider,
      operationsProvider,
      revaliProvider,
      zonaiDbProvider,
      settingsProvider,
      versionsProvider,
      raindropSyncProvider,
      schemaVersionCheckProvider,
    },
  );
}
