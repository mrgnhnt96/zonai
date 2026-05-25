import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/domain/target_os.dart';
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
    if (!kIsCompiled) {
      return;
    }

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

  Future<void> downloadBinary({
    required String version,
    required String targetDestination,
    required TargetOs targetOs,
    required Arch targetArch,
  }) async {
    logger.debug('Downloading binary for $targetOs/$targetArch');
    logger.debug('Version: $version');
    logger.debug('Target destination: $targetDestination');

    final release = await _fetchRelease(version);
    final assetName = _artifactNameFor(targetOs, targetArch);
    final asset = _findAsset(release, assetName);

    final response = await _downloadAsset(asset);

    if (response.statusCode != 200) {
      throw Exception('Failed to download binary for $assetName');
    }

    await _installExecutableFromArchive(targetDestination, response.bodyBytes);
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

    final assetName = _artifactName;
    final asset = _findAsset(release, assetName);
    final response = await _downloadAsset(asset);

    if (response.statusCode != 200) {
      throw Exception('Failed to download update for $assetName');
    }

    await _installExecutableFromArchive(
      Platform.executable,
      response.bodyBytes,
    );
  }

  String _parseVersion(Map<String, dynamic> release) {
    return (release['tag_name'] as String).replaceAll('v', '');
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final response = await _githubGet(Uri.parse('$_apiBase/releases/latest'));

    if (response.statusCode != 200) {
      throw _releaseRequestError('latest release', response.statusCode);
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchRelease(String version) async {
    final tag = version.startsWith('v') ? version : 'v$version';
    final response = await _githubGet(
      Uri.parse('$_apiBase/releases/tags/$tag'),
    );

    if (response.statusCode != 200) {
      throw _releaseRequestError(tag, response.statusCode);
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<http.Response> _githubGet(Uri uri) {
    return http.get(uri, headers: _githubHeaders);
  }

  Future<http.Response> _downloadAsset(Map<String, dynamic> asset) {
    return http.get(
      Uri.parse(asset['url'] as String),
      headers: {..._githubHeaders, 'Accept': 'application/octet-stream'},
    );
  }

  Map<String, String> get _githubHeaders {
    final token =
        Platform.environment['GITHUB_TOKEN'] ??
        Platform.environment['GH_TOKEN'];
    if (token == null || token.isEmpty) {
      return const {};
    }

    return {'Authorization': 'Bearer $token'};
  }

  Exception _releaseRequestError(String release, int statusCode) {
    if (statusCode == 404 && _githubHeaders.isEmpty) {
      return Exception(
        'Failed to get release $release. '
        'This repository is private; set GITHUB_TOKEN or GH_TOKEN.',
      );
    }

    return Exception('Failed to get release $release');
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

  String get _artifactName => _artifactNameFor(.current(), .current());

  String _artifactNameFor(TargetOs targetOs, Arch targetArch) {
    return switch ((targetOs, targetArch)) {
      (.linux, .x64) => 'zonai-linux-x64.zip',
      (.windows, .x64) => 'zonai-windows-x64.zip',
      (.macos, .arm64) => 'zonai-macos-arm64.zip',
      (.macos, .x64) => 'zonai-macos-x64.zip',
      _ => throw UnsupportedError(
        'Unsupported release target: $targetOs/$targetArch',
      ),
    };
  }

  Future<void> _installExecutableFromArchive(
    String targetDestination,
    List<int> bytes,
  ) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.isEmpty) {
      throw Exception('Release archive is empty');
    }

    ArchiveFile? entry;
    for (final file in archive) {
      if (file.name == 'zonai' || file.name == 'zonai.exe') {
        entry = file;
        break;
      }
    }
    entry ??= archive.first;

    await _installExecutable(targetDestination, entry.content);
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
