import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/schema_version/min_schema_version.dart';
import 'package:zonai/src/domain/schema_version/pubspec_lock_parser.dart';

const _packageName = 'zonai_schema';

/// Refuses to run when a target project's actually-*resolved* `zonai_schema`
/// (per its `pubspec.lock`) is older than [kMinSchemaVersion], the floor this
/// CLI supports.
///
/// The constraint a project *declares* only bounds what could resolve, not
/// what did -- a project that never ran `dart pub upgrade` can sit on an older
/// release than its own `^` range allows for.
///
/// There is no auto-fix: the CLI can replace its own executable, but it can't
/// run `dart pub upgrade` inside someone else's project without consent. So
/// this reports and exits rather than repairing.
///
/// Deliberately one threshold rather than a warn/block ladder. With an
/// explicit floor there is no "slightly behind" -- a version at or above it is
/// supported, and one below it is not. Nothing here bounds the *upper* end: a
/// `zonai_schema` newer than this CLI expects is allowed through, and would
/// fail later at whatever it changed.
class SchemaVersionCheck {
  const SchemaVersionCheck({Version? minVersion}) : _minVersion = minVersion;

  /// Testability seam only -- production always falls back to
  /// [kMinSchemaVersion]. A nullable field (rather than parsing the constant
  /// in the constructor) keeps this `const`-constructible.
  final Version? _minVersion;

  Version get minVersion => _minVersion ?? Version.parse(kMinSchemaVersion);

  /// Best-effort, guarded entry point for `zonai_runner.dart`'s `run()`.
  /// No-ops entirely outside a compiled binary (every dev-mode path in this
  /// monorepo resolves `zonai_schema` via `source: path`, where this check
  /// is a guaranteed no-op anyway -- see [check]) and honors
  /// `--no-schema-version-check`.
  Future<int?> ensure() async {
    if (!kIsCompiled) {
      return null;
    }

    if (args['no-schema-version-check'] == true ||
        args['schema-version-check'] == false) {
      return null;
    }

    return check();
  }

  /// The real logic behind [ensure], without the `kIsCompiled`/CLI-flag
  /// guard -- exposed so tests can exercise it directly.
  ///
  /// Returns an exit code when the resolved schema is too old, `null` when it
  /// is supported *or* when there is nothing to compare: no lock file, no
  /// `zonai_schema` entry, or a `source: path` entry that carries no version.
  /// Unknown is not the same as wrong, and refusing to start on a version
  /// nobody could read would break every path-dependency checkout.
  @visibleForTesting
  int? check() {
    final lockFile = fs.file(settings.pubspecLockPath);
    if (!lockFile.existsSync()) {
      return null;
    }

    final resolved = resolvedPackageVersion(
      lockFile.readAsStringSync(),
      packageName: _packageName,
    );

    final version = switch (resolved) {
      ResolvedVersion(version: final v) => v,
      PackageNotFound() || UnresolvableVersion() => null,
    };
    if (version == null) {
      return null;
    }

    if (version >= minVersion) {
      return null;
    }

    return _tooOld(version);
  }

  int _tooOld(Version resolved) {
    logger.error(
      'zonai_schema $resolved is older than the $minVersion this CLI '
      '($kVersion) requires -- the code it generates may call APIs that '
      'version does not have.\n'
      'Run `dart pub upgrade zonai_schema` (or raise the constraint in '
      'pubspec.yaml to ^$minVersion), then rebuild your workers with '
      '`zonai compile`.\n'
      'Pass --no-schema-version-check to proceed anyway.',
    );
    return 1;
  }
}
