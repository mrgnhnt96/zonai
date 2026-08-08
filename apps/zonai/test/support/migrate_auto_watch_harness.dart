import 'dart:async';

import 'package:scoped_deps/scoped_deps.dart';

import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/migrate.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';

/// Standalone harness for [migrate_auto_watch_test.dart].
///
/// Runs [Migrate.auto] against caller-supplied absolute `schemas`/`migrations`
/// directories and then idles so the watcher stays alive. Spawned as its own
/// process (rather than driven in-process) so its working directory can be a
/// disposable fixture project: `raindrop_cli` resolves the owning project for
/// schema introspection from `Directory.current`, and `apps/zonai` has its
/// own `raindrop.yaml` for its internal db that would otherwise get picked up
/// and clobbered.
Future<void> main(List<String> args) async {
  final schemasPath = args[0];
  final migrationsPath = args[1];

  final settings = Settings(
    path: 'zonai.yml',
    migrationsPath: migrationsPath,
    dataPath: '.zonai/data',
    schemasPath: schemasPath,
    extensionsPath: '.zonai/unused/extensions',
    rulesPath: '.zonai/unused/rules',
    operationsPath: '.zonai/unused/operations',
    configPath: '.zonai/unused/config',
    emailTemplatesPath: '.zonai/unused/email_templates',
    rateLimitPath: '.zonai/unused/rate_limit',
    cronsPath: '.zonai/unused/crons',
    imagesPath: '.zonai/unused/images',
    buildSettings: BuildSettings.current(),
    version: kVersion,
  );

  await runScoped(
    () async {
      Migrate().auto();
      // ignore: avoid_print
      print('READY');
      await Completer<void>().future;
    },
    values: {
      settingsProvider.overrideWith(() => settings),
      argsProvider.overrideWith(() => const Args()),
      fsProvider,
      loggerProvider,
      cleanUpProvider,
    },
  );
}
