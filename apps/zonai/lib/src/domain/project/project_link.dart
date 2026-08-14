// dart format width=100
/// Decides whether this project's ops and rules can be linked into the binary
/// that runs them, and prepares the package config that makes it possible.
///
/// The generated entry (`.dart_tool/zonai/project_main.dart`) imports
/// `package:zonai/src/bootstrap.dart`, so it only compiles inside a package
/// graph containing zonai. zonai ships as a standalone binary and is never an
/// application dependency, so for years that graph existed only in
/// `apps/playground` -- meaning the linked binary, and with it in-process
/// dispatch and fine-grained per-operation rate limiting, never applied to a
/// real deployment.
///
/// `--packages` is the way out: `dart compile exe` and `dart run` both take a
/// package config from anywhere, so when zonai's own sources are on disk beside
/// the CLI the two graphs can be merged and the entry compiled against the
/// result. See [mergePackageConfigs] for why the merge has to run in zonai's
/// favour.
///
/// Every answer here is load-bearing in the same quiet way: falling back to
/// worker IPC *works*, so a wrong "cannot link" costs in-process dispatch with
/// nothing failing to show for it. That is why [ProjectLink] carries a reason
/// on every skip, and why the decision lives in one function rather than being
/// re-derived at each of the four call sites.
library;

import 'dart:convert';

import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/project/merged_package_config.dart';
import 'package:zonai/src/utils/zonai_entrypoint.dart';

/// How a project-linked build or re-exec should resolve `package:zonai`.
class ProjectLink {
  /// No linked entry is possible; [skipReason] says why, and callers log it.
  const ProjectLink.skip(String this.skipReason) : packageConfigPath = null, overridden = const [];

  /// The project's own resolution already contains zonai (a `zonai: {path:
  /// ...}` dependency, as apps/playground has). Nothing to write.
  const ProjectLink.direct() : skipReason = null, packageConfigPath = null, overridden = const [];

  /// The project does not depend on zonai, but zonai's sources are on disk, so
  /// the two graphs were merged into [packageConfigPath].
  const ProjectLink.merged({required String this.packageConfigPath, required this.overridden})
    : skipReason = null;

  /// Why a linked entry is impossible, or `null` when it is not.
  final String? skipReason;

  /// The file to pass to `--packages`, or `null` to use the default resolution.
  ///
  /// `null` with [canLink] true is not "no config" -- it is "the project's own
  /// config is already right".
  final String? packageConfigPath;

  /// Packages the project resolved that zonai's graph replaced.
  ///
  /// Each entry is a package the app's own code will be compiled against a
  /// different version of than pub chose for it. Callers log these; a version
  /// substitution nothing mentions is the whole failure mode this file exists
  /// downstream of.
  final List<String> overridden;

  bool get canLink => skipReason == null;
}

/// Decides the link, writing the merged package config when one is needed.
///
/// Writing is not a side effect held apart from the decision on purpose: the
/// decision *is* whether that file could be produced. Answering "yes, link"
/// from a separate predicate and then failing to write the config would hand
/// `dart compile exe` an entry it cannot resolve, which is exactly the failure
/// `865ee7c` shipped twice.
///
/// [findZonaiPackageConfig] is injectable for tests only: [zonaiPackageConfigPath]
/// reads through `dart:io` rather than [fs] (it runs during bootstrap, before
/// any scope exists), so an in-memory filesystem cannot reach it.
ProjectLink resolveProjectLink({
  String? Function() findZonaiPackageConfig = zonaiPackageConfigPath,
  String? Function() findMissingGeneratedSource = missingZonaiGeneratedSource,
}) {
  if (HostWorkerRegistries.forceWorkers) {
    return const ProjectLink.skip('$kForceWorkersEnv is set');
  }

  final projectConfig = projectPackageConfigPath();
  if (projectConfig == null) {
    return const ProjectLink.skip(
      'this project has no .dart_tool/package_config.json -- run `dart pub get` '
      'to resolve it; ops and rules will run as worker processes until then',
    );
  }

  if (_resolvesZonai(projectConfig)) {
    return const ProjectLink.direct();
  }

  final zonaiConfig = findZonaiPackageConfig();
  if (zonaiConfig == null) {
    return const ProjectLink.skip(
      'package:zonai is not resolvable from this project, and zonai\'s own '
      'sources are not on disk beside this binary, so there is no package graph '
      'to merge with it -- ops and rules will run as worker processes',
    );
  }

  // Present is not the same as buildable. `lib/gen/` is gitignored and written
  // by `zonai compile`, so a zonai checkout that has not been built resolves
  // and merges perfectly and then fails inside `dart compile exe` on an import
  // that does not exist -- with no fallback, because the decision to link was
  // already made. Skipping is the answer the rest of this function gives to
  // "the graph cannot be formed"; an unbuildable graph is that same answer.
  if (findMissingGeneratedSource() case final missing?) {
    return ProjectLink.skip(
      'zonai\'s sources are on disk but not built -- $missing is missing, and '
      'a linked build compiles against it. Run `zonai compile` (or `sip run '
      'bootstrap test`) in that checkout to generate it; ops and rules will '
      'run as worker processes until then',
    );
  }

  final merged = writeMergedPackageConfig(
    projectConfigPath: projectConfig,
    zonaiConfigPath: zonaiConfig,
    outputPath: settings.mergedPackageConfigPath,
  );
  if (merged == null) {
    return const ProjectLink.skip(
      'could not merge this project\'s package graph with zonai\'s -- one of '
      'the two configs is missing or unreadable; ops and rules will run as '
      'worker processes',
    );
  }

  return ProjectLink.merged(
    packageConfigPath: settings.mergedPackageConfigPath,
    overridden: merged.overridden,
  );
}

/// Says out loud which packages zonai's graph took over.
///
/// Called once per flow, by whoever resolved the link -- not by
/// [ProjectBinary.compile], which some of those flows call afterwards, because
/// saying it twice per build trains people to stop reading it.
///
/// Silent when nothing was overridden, which is the normal case: a workspace
/// project and the CLI beside it agree on almost all of their graph.
void logOverriddenPackages(ProjectLink link) {
  if (link.overridden.isEmpty) return;

  logger.warn(
    'Linking against zonai\'s copy of ${link.overridden.length} package(s) '
    'this project resolved differently: ${link.overridden.join(', ')}. '
    'The project\'s own code is compiled against those versions, not the ones '
    'pub chose for it.',
  );
}

/// Whether `package:zonai` resolves from the project being built or served.
///
/// True only for a project that depends on zonai directly. That is the
/// uninteresting case -- it needs no merged config -- and it is false in every
/// real deployment, so this answers strictly less than [resolveProjectLink]
/// and should not be used to decide whether to link.
bool projectResolvesZonai() {
  final path = projectPackageConfigPath();
  if (path == null) return false;

  return _resolvesZonai(path);
}

/// The nearest existing `.dart_tool/package_config.json` at or above the
/// project, or `null` when pub has never resolved it.
///
/// Nearest wins and the walk stops there: an ancestor's config is a different
/// resolution answering a different question.
String? projectPackageConfigPath() {
  for (final path in _packageConfigCandidates()) {
    if (fs.file(path).existsSync()) return path;
  }

  return null;
}

bool _resolvesZonai(String path) {
  try {
    if (json.decode(fs.file(path).readAsStringSync()) case {'packages': final List<dynamic> pkgs}) {
      return pkgs.any((package) => package is Map && package['name'] == 'zonai');
    }
  } catch (_) {
    // An unreadable or half-written package_config is not a linkable project;
    // fall back to workers rather than failing the build.
  }

  return false;
}

/// `.dart_tool/package_config.json` candidates, nearest first.
///
/// A pub workspace writes exactly one package config, at the workspace root
/// -- members get none. So the project being built is very often a directory
/// with no `.dart_tool` of its own (apps/playground here, apps/server in a
/// consumer repo), and looking only beside its pubspec would report every
/// workspace member as unable to link.
Iterable<String> _packageConfigCandidates() sync* {
  var dir = fs.file(settings.packageConfigPath).parent.parent.absolute;

  while (true) {
    yield fs.path.join(dir.path, '.dart_tool', 'package_config.json');

    if (dir.path == dir.parent.path) return;
    dir = dir.parent;
  }
}
