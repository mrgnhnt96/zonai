import 'dart:io';

import 'package:raindrop_cli/src/core/dart_executable.dart';

import '../deps/settings.dart';

String get _projectRoot => settings.basePath ?? Directory.current.path;

/// Configures and resolves the Dart SDK executable for zonai subprocesses.
Future<String> resolveDartExecutable() async {
  DartExecutable.configuredPath = settings.dartSdkPath;
  return DartExecutable.resolve(projectRoot: _projectRoot);
}

/// Applies [settings.dartSdkPath] before invoking raindrop_cli (migrations).
void configureRaindropDartSdk() {
  DartExecutable.configuredPath = settings.dartSdkPath;
}

/// The bare version string of the Dart SDK at [dartExecutablePath] --
/// `3.12.0`, and nothing else from the line it came out of -- or `null` when
/// it cannot be established.
///
/// Message text only. It is written beside the VM snapshot hash in a `.sdk`
/// sidecar (see `snapshot_sdk_stamp.dart`) so a refusal can say "built by Dart
/// 3.13.2, this host needs 3.12.0" instead of printing two hex strings at
/// somebody. `sdkVmSnapshotHash` is the value that actually gets compared, and
/// a version disagreeing with the hash is the version being wrong.
///
/// The bare version comes back rather than the whole `--version` line for two
/// reasons: it is the shape the host side is baked in with (CI pins `sdk:
/// "3.12.0"`, and `hostDartSdkVersion` reads that back verbatim), so both
/// halves of that sentence match; and the stamp writes the version as one
/// line, which the line's build date and platform have no use for.
///
/// `null` means UNKNOWN, as everywhere in this mechanism, and covers an
/// executable that cannot be run, exits non-zero, or prints something this
/// cannot parse. It never throws: it runs immediately after a compile that
/// already succeeded, where a throw would lose the artifact.
Future<String?> dartSdkVersion(String dartExecutablePath) async {
  try {
    final result = await Process.run(dartExecutablePath, ['--version']);
    if (result.exitCode != 0) return null;

    // `--version` has moved between the two streams across SDK releases --
    // 3.12.0 prints it on stdout, older ones printed it on stderr -- so both
    // are searched rather than picking the one that happens to be right today.
    for (final stream in [result.stdout, result.stderr]) {
      if (stream is! String) continue;
      if (_versionPattern.firstMatch(stream) case final match?) {
        return match.group(1);
      }
    }
    return null;
  } on Object {
    return null;
  }
}

/// The version out of `Dart SDK version: 3.12.0 (stable) (Fri May 8 ...) on
/// "macos_arm64"`. Everything up to the first space, so a pre-release like
/// `3.13.0-100.0.dev` comes back whole.
final _versionPattern = RegExp(r'Dart SDK version:\s+(\S+)');
