import 'dart:convert';
import 'dart:io' hide stdin;

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/arch.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/native_library_stamp.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/domain/target_os.dart';
import 'package:zonai_logger/zonai_logger.dart';

const _repo = 'mrgnhnt96/zonai';
const _apiBase = 'https://api.github.com/repos/$_repo';
const _migrationGuideUrl = 'https://docs.zonai.dev/cli/upgrading';

/// Whether moving the CLI from [from] to [to] crosses a semver `^`-breaking
/// boundary (major once >= 1.0, otherwise minor) -- the same cohort check
/// used elsewhere for schema version drift.
bool isBreakingCliUpgrade({required String from, required String to}) {
  final fromVersion = Version.parse(from);
  final toVersion = Version.parse(to);
  return !VersionConstraint.compatibleWith(fromVersion).allows(toVersion);
}

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

    if (args['no-version-check'] == true || args['version-check'] == false) {
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

    // Same escape hatch as [checkForUpdate] — CI/stress/scripts pass
    // `--no-version-check` when the pinned project version intentionally
    // differs from the CLI under test (e.g. local unreleased builds).
    if (args['no-version-check'] == true || args['version-check'] == false) {
      logger.warn(
        'Version mismatch ignored (--no-version-check): '
        'project=${settings.version} cli=$kVersion',
      );
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

  /// Prints the current and latest version for explicit version checks.
  Future<void> printVersionCheck() async {
    if (!kIsCompiled) {
      logger.info('Current version: v$current');
      logger.info('Version checks are only available in compiled builds.');
      return;
    }

    final latestVersion = await latest();
    logger.info('Current version: v$current');

    if (latestVersion == current) {
      logger.info('You are on the latest version.');
      return;
    }

    logger.info('Latest version: v$latestVersion');
    logger.info('Run `zonai version update` to install.');
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

  /// Downloads the [targetOs]/[targetArch] shared libraries for [version]
  /// into [destination], stamping each so a cross-compiled binary running
  /// there keeps them instead of self-extracting its own.
  ///
  /// `dart compile exe --target-os` cross-compiles the executable format but
  /// not the native-library bytes embedded in it, so a host binary built for
  /// another platform carries the *build* machine's libraries. These assets
  /// are built on a native runner per target (see .github/workflows) and are
  /// the same ones embedded in that target's published binary.
  Future<void> downloadNativeLibs({
    required String version,
    required String destination,
    required TargetOs targetOs,
    required Arch targetArch,
  }) async {
    logger.debug('Downloading native libraries for $targetOs/$targetArch');

    final release = await _fetchRelease(version);
    final assetName = _nativeLibsArtifactNameFor(targetOs, targetArch);
    final asset = _findAsset(release, assetName);

    final response = await _downloadAsset(asset);
    if (response.statusCode != 200) {
      throw Exception('Failed to download native libraries for $assetName');
    }

    final archive = ZipDecoder().decodeBytes(response.bodyBytes);
    if (archive.isEmpty) {
      throw Exception('Native library archive is empty: $assetName');
    }

    final directory = fs.directory(destination);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    for (final entry in archive) {
      if (!entry.isFile) continue;

      // Flat by construction (see tool/ci/package_native_lib_assets.sh); take
      // the basename anyway so a nested entry can't escape [destination].
      final name = fs.path.basename(entry.name);
      final path = fs.path.join(directory.path, name);

      await _installLibrary(path, entry.content);
      writeNativeLibraryStamp(
        path,
        version: version,
        targetOs: targetOs,
        targetArch: targetArch,
      );
      logger.debug('Installed native library: $path');
    }
  }

  /// Writes a downloaded library via a temp file + rename, so a concurrent
  /// `dlopen` can never map a partially-written file -- the same reason
  /// resqlite_native.dart's `_writeLibraryBytes` does it this way.
  Future<void> _installLibrary(String path, List<int> bytes) async {
    final destination = fs.file(path);
    final temp = fs.file('$path.tmp-$pid');

    await temp.writeAsBytes(bytes, flush: true);
    if (!Platform.isWindows) {
      await process.run('chmod', ['755', temp.path]);
    }
    temp.renameSync(destination.path);
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
      logger.info('Zonai is already up to date (v$current).');
      return;
    }

    logger.info('Downloading Zonai v$targetVersion...');

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

    settings.version = targetVersion;
    final breakingUpgrade = isBreakingCliUpgrade(
      from: current,
      to: targetVersion,
    );

    if (Platform.isWindows) {
      logger.info('Update downloaded. It will be applied when the CLI exits.');
    } else {
      logger.info('Updated to Zonai v$targetVersion.');
    }

    if (breakingUpgrade) {
      logger.warn(
        'This update may include breaking changes. '
        'See the migration guide: $_migrationGuideUrl',
      );
    }
  }

  String _parseVersion(Map<String, dynamic> release) {
    return (release['tag_name'] as String).replaceAll('v', '');
  }

  /// The newest zonai *CLI* release.
  ///
  /// Not `/releases/latest`: this repo also publishes per-package releases
  /// (`zonai_schema-v0.1.0`, `zonai_client-v0.1.0`), and GitHub's "latest" is
  /// simply the most recent non-draft, non-prerelease one. On 2026-08-10 a
  /// package release took that slot, so the update check reported a new
  /// version of "zonai_client-0.1.0" and `version update` then failed looking
  /// for a `zonai-<os>-<arch>.zip` asset that release does not have.
  ///
  /// Releases come back newest-first, so the first `v<semver>` tag wins.
  /// draft/prerelease are filtered to keep `/releases/latest`'s semantics.
  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final response = await _githubGet(
      Uri.parse('$_apiBase/releases?per_page=100'),
    );

    if (response.statusCode != 200) {
      throw _releaseRequestError('latest release', response.statusCode);
    }

    final releases = json.decode(response.body) as List<dynamic>;
    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;
      if (release['draft'] == true || release['prerelease'] == true) continue;

      if (release['tag_name'] case final String tag
          when _cliReleaseTag.hasMatch(tag)) {
        return release;
      }
    }

    throw Exception(
      'No zonai CLI release found: none of the latest ${releases.length} '
      'releases is tagged v<major>.<minor>.<patch>.',
    );
  }

  static final _cliReleaseTag = RegExp(r'^v\d+\.\d+\.\d+$');

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
    return 'zonai-${_targetSlug(targetOs, targetArch)}.zip';
  }

  String _nativeLibsArtifactNameFor(TargetOs targetOs, Arch targetArch) {
    return 'native-libs-${_targetSlug(targetOs, targetArch)}.zip';
  }

  /// The `<os>-<arch>` half of a release asset name. Both asset families are
  /// published per target by release.yml and must agree on this spelling.
  String _targetSlug(TargetOs targetOs, Arch targetArch) {
    return switch ((targetOs, targetArch)) {
      (.linux, .x64) => 'linux-x64',
      (.linux, .arm64) => 'linux-arm64',
      (.windows, .x64) => 'windows-x64',
      (.macos, .arm64) => 'macos-arm64',
      (.macos, .x64) => 'macos-x64',
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

extension InteractiveLogger on Logger {
  Future<bool> confirm(String message, {bool defaultYes = false}) async {
    final hint = defaultYes ? '[Y/n]' : '[y/N]';

    if (stdin.hasTerminal) {
      info('$message $hint');
      stdout.write('> ');
    } else {
      info(message);
    }

    final line = stdin.readLineSync()?.trim().toLowerCase();
    if (line == null) {
      return defaultYes;
    }

    return switch (line) {
      'y' || 'yes' => true,
      'n' || 'no' => false,
      '' => defaultYes,
      _ => defaultYes,
    };
  }
}
