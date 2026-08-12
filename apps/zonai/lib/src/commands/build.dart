import 'dart:io' show Platform;

import 'package:file/file.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/commands/compile.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/migrate.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/versions.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/project/project_binary.dart';
import 'package:zonai/src/domain/project/project_runtime.dart';

const _usage = '''
Usage: zonai build

Options:
  -h, --help      Show help information
''';

Future<int> build() async {
  if (args.help) {
    print(_usage);
    return 1;
  }

  if (fs.directory(settings.buildDirectory) case final dir
      when dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }

  logger.info('Building zonai artifacts');
  logger.debug('Building for ${settings.buildSettings}');

  if (await compile(settings.buildSettings) case final exitCode
      when exitCode != 0) {
    return exitCode;
  }

  // copy Email templates
  if (fs.directory(settings.emailTemplatesPath) case final dir
      when dir.existsSync()) {
    final emails = dir.listSync();
    if (emails.isNotEmpty) {
      fs
          .directory(settings.buildEmailTemplatesPath)
          .createSync(recursive: true);
    }

    for (final email in emails) {
      if (email is File) {
        fs
            .file(email.path)
            .copySync(
              fs.path.join(
                settings.buildEmailTemplatesPath,
                fs.path.basename(email.path),
              ),
            );
      }
    }
  }

  // copy SQL migrations
  final migrations = await migrate.migrations();
  String target;
  for (final migration in migrations) {
    target = fs.path.join(settings.buildMigrationsPath, '${migration.tag}.sql');
    final file = fs.file(target)..createSync(recursive: true);
    await file.writeAsString(migration.sql);
  }

  if (fs.file(settings.path) case final file when file.existsSync()) {
    file.copySync(settings.buildSettingsPath);
  }

  if (fs.file(fs.path.join(settings.imagesPath, 'favicon.ico')) case final file
      when file.existsSync()) {
    fs.directory(settings.buildImagesPath).createSync(recursive: true);
    file.copySync(fs.path.join(settings.buildImagesPath, 'favicon.ico'));
  }

  // Cross-compiling produces executables for the target carrying *this*
  // machine's native libraries (see downloadNativeLibs), and that is true of
  // every executable in the bundle, not just a linked host binary: the worker
  // .exe files compiled by `compile` above are `dart compile exe --target-os`
  // builds of this same source. Fetching the target's real libraries is
  // therefore unconditional here -- it used to sit inside the linked-binary
  // branch below, which meant a project that can't link (the normal case:
  // nothing depends on package:zonai) shipped workers whose only copy of
  // resqlite/argon2 was the build host's.
  final nativeLibError = switch (settings.buildSettings
      .targetsCurrentPlatform()) {
    true => null,
    false => await _bundleTargetNativeLibs(),
  };

  // Project-linked binary with in-process ops/rules (full CLI surface), when
  // this project can have one. Otherwise bundle the published binary, which
  // drives the Mailman workers compiled above -- the same pairing every
  // pre-project-linking build shipped.
  if (projectLinkSkipReason() case final reason?) {
    logger.info('Bundling the published zonai binary: $reason');
    if (nativeLibError != null) {
      // Not fatal: the published binary is built for the target, so its own
      // embedded libraries are correct, and a worker asks it for them rather
      // than trusting its own (see resqlite_native.dart's
      // `_requestFromSpawner`). What's lost is the fallback for when that ask
      // fails -- which now surfaces as a refusal to install, not as a
      // wrong-architecture library written over the shared path.
      logger.warn(
        'Bundling without the target\'s native libraries: $nativeLibError. '
        'Workers will depend on the host binary answering their native '
        'library requests, with no on-disk fallback if it cannot.',
      );
    }
    await _bundlePublishedBinary();
    return 0;
  }

  // A linked binary has no such host above it to ask, so the fetched
  // libraries are the only correct ones it will ever see -- without them,
  // don't ship it at all; fall back to the published binary for the target.
  if (nativeLibError != null) {
    logger.warn('Bundling the published zonai binary: $nativeLibError');
    await _bundlePublishedBinary();
    return 0;
  }

  if (await ProjectBinary().compile(buildSettings: settings.buildSettings)
      case final exitCode when exitCode != 0) {
    return exitCode;
  }

  return 0;
}

/// Downloads the target's shared libraries into the bundle, returning `null`
/// on success or a reason the caller should fall back.
Future<String?> _bundleTargetNativeLibs() async {
  final build = settings.buildSettings;
  logger.info(
    'Fetching ${build.targetOs.name}/${build.targetArch.name} native '
    'libraries for the bundle',
  );

  try {
    await versions.downloadNativeLibs(
      // kVersion, not settings.version: the binaries that read this stamp --
      // a linked host binary, and the worker executables either way -- are
      // compiled from *this* CLI's source, so they must pair with this
      // release's libraries, and `hasCurrentNativeLibraryStamp` compares the
      // stamp against the reader's own kVersion.
      // The stock-binary fallback downloads settings.version and is stamped
      // to match, but here the two can diverge -- `--no-version-check` lets a
      // project pin a version the CLI isn't -- and a stamp that doesn't match
      // the binary reading it just stops applying, silently handing the
      // wrong-platform embedded copy back.
      version: kVersion,
      destination: settings.buildNativeLibDirectory,
      targetOs: build.targetOs,
      targetArch: build.targetArch,
    );
    return null;
  } catch (e) {
    return 'could not fetch native libraries for '
        '${build.targetOs.name}/${build.targetArch.name} ($e)';
  }
}

/// Why this build cannot produce a project-linked binary, or `null` when it
/// can.
///
/// Exposed for tests: each branch is a silent fallback to worker IPC, and the
/// reason is the only thing that distinguishes "correctly fell back" from
/// "quietly lost in-process dispatch".
String? projectLinkSkipReason() {
  if (forceWorkers) {
    return '$kForceWorkersEnv is set';
  }

  if (!projectResolvesZonai()) {
    return 'package:zonai is not resolvable from this project -- ops and '
        'rules will run as worker processes. Add `zonai: {path: ...}` to '
        'dev_dependencies to link them in-process instead.';
  }

  // Cross-target is deliberately absent: `dart compile exe --target-os` can
  // link for another platform, and the native libraries it would get wrong
  // are supplied separately by _bundleTargetNativeLibs.
  return null;
}

/// Puts a stock `zonai` at `settings.buildExecutablePath`.
///
/// Prefers the running executable when it is already the right binary for the
/// target: it costs nothing, and -- unlike the download -- needs no GitHub
/// token, which matters because zonai's releases are private. `kIsCompiled`
/// is the guard that this process *is* a zonai binary rather than the Dart VM
/// running from source, where [Platform.executable] is `dart`.
Future<void> _bundlePublishedBinary() async {
  if (settings.buildSettings.targetsCurrentPlatform() && kIsCompiled) {
    fs.file(Platform.executable).copySync(settings.buildExecutablePath);
    return;
  }

  await versions.downloadBinary(
    version: settings.version,
    targetDestination: settings.buildExecutablePath,
    targetOs: settings.buildSettings.targetOs,
    targetArch: settings.buildSettings.targetArch,
  );
}
