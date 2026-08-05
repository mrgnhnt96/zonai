import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Result of [resolvedPackageVersion].
sealed class ResolvedPackageVersion {
  const ResolvedPackageVersion();
}

/// [packageName] resolves to a real, comparable semver version (`source:
/// hosted` with a parsable `version:`).
final class ResolvedVersion extends ResolvedPackageVersion {
  const ResolvedVersion(this.version);

  final Version version;
}

/// [packageName] isn't listed under `packages:` at all.
final class PackageNotFound extends ResolvedPackageVersion {
  const PackageNotFound();
}

/// [packageName] is listed but nothing comparable could be extracted --
/// a non-`hosted` source (`path`/`git`/`sdk`, which routinely carries no
/// `version:` at all, or a placeholder rather than a real release), a
/// missing `version:` key, or a `version:` string that isn't valid semver.
final class UnresolvableVersion extends ResolvedPackageVersion {
  const UnresolvableVersion();
}

/// Parses [lockContent] (a `pubspec.lock`'s raw text) for [packageName]'s
/// actually-resolved version.
///
/// Never throws: tolerates empty/whitespace content, a non-map root, a
/// missing/non-map `packages:`, a missing/non-map package entry, a
/// non-`hosted` source, and a missing or unparsable `version:`.
ResolvedPackageVersion resolvedPackageVersion(
  String lockContent, {
  required String packageName,
}) {
  if (lockContent.trim().isEmpty) {
    return const PackageNotFound();
  }

  final Object? parsed;
  try {
    parsed = loadYaml(lockContent);
  } catch (_) {
    return const UnresolvableVersion();
  }

  if (parsed is! Map) {
    return const UnresolvableVersion();
  }

  final packages = parsed['packages'];
  if (packages is! Map) {
    return const PackageNotFound();
  }

  final entry = packages[packageName];
  if (entry is! Map) {
    return const PackageNotFound();
  }

  if (entry['source'] != 'hosted') {
    return const UnresolvableVersion();
  }

  final versionString = entry['version'];
  if (versionString is! String) {
    return const UnresolvableVersion();
  }

  try {
    return ResolvedVersion(Version.parse(versionString));
  } catch (_) {
    return const UnresolvableVersion();
  }
}
