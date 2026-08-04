import 'dart:convert';
import 'dart:io' show Platform;

import 'package:meta/meta.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/gen/internal/raindrop/raindrop_bundle.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/raindrop/pubspec_overrides_merge.dart';

/// Materializes the embedded raindrop/raindrop_sqlite bundle (baked into the
/// compiled zonai binary with explicit permission from raindrop's original
/// author) into the current project's `.zonai/internal/`, and wires it up
/// via `pubspec_overrides.yaml` -- so a third party using the compiled
/// `zonai` CLI never needs pub.dev or git access to raindrop itself.
///
/// Runs before every command (see `zonai_runner.dart`); the stamp file makes
/// repeat invocations (including the second `runZonai()` re-entry from a
/// compiled project binary) effectively free once in sync.
class RaindropSync {
  const RaindropSync();

  /// Best-effort: never throws, never blocks the caller's actual command.
  /// No-ops in dev/source runs and when disabled via `--no-raindrop-sync`.
  Future<void> ensure({bool force = false}) async {
    if (!kIsCompiled) {
      return;
    }

    if (args['no-raindrop-sync'] == true || args['raindrop-sync'] == false) {
      return;
    }

    try {
      await syncNow(force: force);
    } catch (e, stack) {
      logger.debug('Raindrop sync failed: $e\n$stack');
    }
  }

  /// The real logic behind [ensure], without the `kIsCompiled`/CLI-flag
  /// guards or the catch-and-log wrapper -- exposed so tests can exercise it
  /// directly (`ensure` is only meaningfully different in a compiled binary).
  @visibleForTesting
  Future<void> syncNow({bool force = false}) async {
    final stamp = readStamp();
    final bundleChanged = stamp?.hash != kRaindropBundleHash;

    if (!force && !bundleChanged) {
      return;
    }

    _writeBundleFiles();

    final desired = {
      'raindrop': _posix(settings.internalRaindropPath),
      'raindrop_sqlite': _posix(settings.internalRaindropSqlitePath),
    };

    final overridesFile = fs.file(settings.pubspecOverridesPath);
    final existing = overridesFile.existsSync()
        ? overridesFile.readAsStringSync()
        : '';

    final result = mergePathOverrides(
      existing,
      desired: desired,
      previouslyOwned: stamp?.overrides ?? const {},
    );

    if (result.skipped.isNotEmpty) {
      final names = result.skipped.keys.join(', ');
      logger.warn(
        'Raindrop sync: leaving the existing dependency_overrides for '
        '$names in ${settings.pubspecOverridesPath} untouched -- it was not '
        'written by zonai. Remove it there if you want zonai to manage it.',
      );
    }

    if (result.changed) {
      overridesFile.parent.createSync(recursive: true);
      overridesFile.writeAsStringSync(result.content);
    }

    _writeStamp(RaindropSyncStamp(hash: kRaindropBundleHash, overrides: result.applied));

    final pubspecExists = fs.file(settings.pubspecPath).existsSync();
    if ((bundleChanged || result.changed) && pubspecExists) {
      final pubGet = await process.runDart(['pub', 'get']);
      if (pubGet.exitCode != 0) {
        logger.warn('Raindrop sync: `dart pub get` failed after syncing raindrop.');
        logger.debug('${pubGet.stderr}');
      }
    }
  }

  void _writeBundleFiles() {
    for (final dir in [
      settings.internalRaindropPath,
      settings.internalRaindropSqlitePath,
    ]) {
      final directory = fs.directory(dir);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }

    for (final entry in raindropBundleFiles.entries) {
      final file = fs.file(fs.path.join(settings.internalDirectory, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }

  RaindropSyncStamp? readStamp() {
    final file = fs.file(settings.internalRaindropStampPath);
    if (!file.existsSync()) {
      return null;
    }

    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return RaindropSyncStamp.fromJson(decoded as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void _writeStamp(RaindropSyncStamp stamp) {
    final file = fs.file(settings.internalRaindropStampPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(stamp.toJson()));
  }

  bool get isUpToDate => readStamp()?.hash == kRaindropBundleHash;

  String _posix(String path) =>
      Platform.pathSeparator == '/' ? path : path.replaceAll(r'\', '/');
}

class RaindropSyncStamp {
  const RaindropSyncStamp({required this.hash, required this.overrides});

  factory RaindropSyncStamp.fromJson(Map<String, dynamic> json) {
    return RaindropSyncStamp(
      hash: json['hash'] as String,
      overrides: {
        for (final entry in (json['overrides'] as Map).entries)
          entry.key as String: entry.value as String,
      },
    );
  }

  final String hash;
  final Map<String, String> overrides;

  Map<String, dynamic> toJson() => {'hash': hash, 'overrides': overrides};
}
