import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/schema_version/pubspec_lock_parser.dart';
import 'package:zonai/src/domain/schema_version/schema_version_severity.dart';

const _packageName = 'zonai_schema';

/// Checks whether a target project's actually-*resolved* `zonai_schema`
/// (per its `pubspec.lock`) is new enough for this build of the CLI.
/// `zonai_schema` ships 1:1 with `kVersion`; the scaffolded `^$kVersion`
/// constraint (see `init_actions.dart`) only bounds what *could* resolve,
/// not what did -- a project that never ran `dart pub upgrade` can still be
/// on an older, actually-resolved release.
///
/// Unlike [Versions.assertVersion], there is no auto-fix action available --
/// the CLI can replace its own executable, but it can't safely run
/// `dart pub upgrade` inside someone else's project without consent. So this
/// is comparison-based (resolved < required), not equality-based, and reacts
/// with severity that scales with how far behind [resolved] is (see
/// [schemaVersionSeverity]).
class SchemaVersionCheck {
  const SchemaVersionCheck({Version? requiredVersion}) : _requiredVersion = requiredVersion;

  /// Testability seam only -- production always falls back to [kVersion].
  /// A nullable field (rather than parsing `kVersion` directly in the
  /// constructor) keeps this `const`-constructible like [RaindropSync].
  final Version? _requiredVersion;

  Version get requiredVersion => _requiredVersion ?? Version.parse(kVersion);

  /// Best-effort, guarded entry point for `zonai_runner.dart`'s `run()`.
  /// No-ops entirely outside a compiled binary (every dev-mode path in this
  /// monorepo resolves `zonai_schema` via `source: path`, where this check
  /// is a guaranteed no-op anyway -- see [check]) and honors
  /// `--no-schema-version-check`.
  Future<int?> ensure() async {
    if (!kIsCompiled) {
      return null;
    }

    if (args['no-schema-version-check'] == true || args['schema-version-check'] == false) {
      return null;
    }

    return check();
  }

  /// The real logic behind [ensure], without the `kIsCompiled`/CLI-flag
  /// guard -- exposed so tests can exercise it directly.
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

    return switch (schemaVersionSeverity(resolved: version, required: requiredVersion)) {
      SchemaVersionSeverity.ok => null,
      SchemaVersionSeverity.warn => _warn(version),
      SchemaVersionSeverity.block => _block(version),
    };
  }

  int? _warn(Version resolved) {
    logger.warn(
      'zonai_schema $resolved is older than this CLI ($kVersion). '
      'Run `dart pub upgrade zonai_schema` (or `dart pub upgrade`) to update.',
    );
    return null;
  }

  int _block(Version resolved) {
    logger.error(
      'zonai_schema $resolved is too far behind this CLI ($kVersion) and '
      "crosses a breaking-change boundary -- the CLI's generated code may "
      'not be compatible.\n'
      'Run `dart pub upgrade zonai_schema` (or `dart pub upgrade`) to '
      'update, or pass --no-schema-version-check to proceed anyway.',
    );
    return 1;
  }
}
