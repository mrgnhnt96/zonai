import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';

const _repo = 'mrgnhnt96/zonai';
const _apiBase = 'https://api.github.com/repos/$_repo';

class Versions {
  const Versions();

  String get current => kVersion;

  /// Checks for a new version of Zonai and warns the user if there is an update available.
  ///
  /// Disable by passing `--no-version-check`
  Future<void> checkForUpdate() async {
    if (args['no-version-check'] case true) {
      return;
    }

    final latest = await this.latest();

    if (latest == current) {
      return;
    }

    logger.warn('A new version of Zonai is available: $latest');
  }

  Future<int?> assertVersion() async {
    final settings = Settings.load();

    if (settings.version == kVersion) {
      return null;
    }

    logger.error(
      'Version mismatch: $Settings.version (${settings.version}) != $kVersion',
    );
    final confirmed = await logger.confirm(
      'Do you want to download ${settings.version}?',
    );

    if (!confirmed) {
      throw Exception(
        'Version mismatch: $Settings.version (${settings.version}) != $kVersion',
      );
    }

    await downloadUpdate(settings.version);
    logger.warn('Updated to ${settings.version}, please restart the CLI');

    return null;
  }

  Future<String> latest() async {
    if (!kIsCompiled) {
      return kVersion;
    }

    try {
      return _parseVersion(await _fetchLatestRelease());
    } catch (e, stack) {
      if (!kIsCompiled) {
        logger.error('$e', 'Failed to get latest version', stack);
      } else {
        logger.debug('Failed to get latest version: $e');
      }

      return kVersion;
    }
  }

  /// Returns the latest version if there is an update, otherwise null.
  Future<String?> hasUpdate() async {
    if (await latest() case final latest when latest != current) {
      return latest;
    }

    return null;
  }

  Future<void> downloadUpdate([String? version]) async {
    if (!kIsCompiled) {
      throw Exception('Cannot download update for non-compiled version');
    }

    final release = switch (version?.replaceAll('v', '')) {
      final String value => await _fetchRelease(value),
      _ => await _fetchLatestRelease(),
    };

    final targetVersion = _parseVersion(release);
    if (targetVersion == current) {
      return;
    }

    final asset = _findAsset(release, _artifactName);
    final response = await http.get(
      Uri.parse(asset['browser_download_url'] as String),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to download update for $_artifactName');
    }

    await _installExecutable(Platform.executable, response.bodyBytes);
  }

  String _parseVersion(Map<String, dynamic> release) {
    return (release['tag_name'] as String).replaceAll('v', '');
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final response = await http.get(Uri.parse('$_apiBase/releases/latest'));

    if (response.statusCode != 200) {
      throw Exception('Failed to get latest version');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchRelease(String version) async {
    final response = await http.get(
      Uri.parse('$_apiBase/releases/tags/v$version'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get release v$version');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> _findAsset(
    Map<String, dynamic> release,
    String assetName,
  ) {
    for (final asset in release['assets'] as List<dynamic>) {
      final map = asset as Map<String, dynamic>;
      if (map['name'] == assetName) {
        return map;
      }
    }

    throw Exception('Release asset not found: $assetName');
  }

  String get _artifactName {
    if (Platform.isLinux) {
      return 'zonai-linux-x64';
    }

    if (Platform.isWindows) {
      return 'zonai-windows-x64';
    }

    if (Platform.isMacOS) {
      return switch (Abi.current()) {
        Abi.macosArm64 => 'zonai-macos-arm64',
        Abi.macosX64 => 'zonai-macos-x64',
        _ => throw UnsupportedError(
          'Unsupported macOS architecture: ${Abi.current()}',
        ),
      };
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  Future<void> _installExecutable(
    String executablePath,
    List<int> bytes,
  ) async {
    final executable = fs.file(executablePath);
    final directory = executable.parent;
    final baseName = fs.path.basename(executablePath);
    final newPath = fs.path.join(directory.path, '$baseName.new');
    final oldPath = fs.path.join(directory.path, '$baseName.old');
    final newFile = fs.file(newPath);

    await newFile.writeAsBytes(bytes, flush: true);

    if (Platform.isWindows) {
      await _installExecutableWindows(executablePath, newPath);
      return;
    }

    await process.run('chmod', ['755', newPath]);

    if (fs.file(oldPath).existsSync()) {
      fs.file(oldPath).deleteSync();
    }

    if (executable.existsSync()) {
      executable.renameSync(oldPath);
    }

    newFile.renameSync(executablePath);
  }

  Future<void> _installExecutableWindows(
    String executablePath,
    String newPath,
  ) async {
    final scriptPath = fs.path.join(
      fs.file(executablePath).parent.path,
      'zonai-update.bat',
    );

    await fs
        .file(scriptPath)
        .writeAsString(
          '@echo off\r\n'
          'timeout /t 1 /nobreak > nul\r\n'
          'del /F /Q "$executablePath"\r\n'
          'move /Y "$newPath" "$executablePath"\r\n'
          'del /F /Q "%~f0"\r\n',
        );

    await process.start('cmd', [
      '/c',
      scriptPath,
    ], mode: ProcessStartMode.detached);
  }
}

// TODO: Implement interactive logger extension
extension InteractiveLogger on Logger {
  Future<bool> confirm(String message) async {
    info(message);
    return true;
  }
}
