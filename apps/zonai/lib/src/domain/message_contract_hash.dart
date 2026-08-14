import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:zonai/src/domain/dart_source_normalizer.dart';

import '../deps/fs.dart';
import '../deps/settings.dart';

/// A fingerprint of the *vocabulary* host and worker use inside the IPC frame,
/// as opposed to `IpcCodec.version`, which fingerprints the frame itself.
///
/// The two are independent, and only one of them was being checked. `066b88b`
/// changed how a message is said, and the protocol stamp
/// (`ipc_protocol_stamp.dart`) catches that. #25 changed what can be said --
/// it added `custom` to `RateLimitOperation`, leaving `IpcCodec.version` at
/// `1` because the framing genuinely had not changed. A worker compiled before
/// that value existed passed the protocol check, started, and then died inside
/// `RateLimitRequest.fromRequest` with `No enum value with that name:
/// "custom"`, surfacing as an HTTP 503 carrying a Dart stack trace. Adding an
/// enum value, a required request field, a renamed payload key or a new
/// `Request` subtype are all invisible to a codec-version check and all break
/// the same way.
///
/// ## Which files are hashed, and why those
///
/// Every Dart file inside `zonai_schema`'s `lib/` reachable, through `import`
/// / `export` / `part`, from any file under [_handlersDirectory]. The handlers
/// are where `Request`/`Response` live, so the closure over what they depend
/// on is, by construction, "everything the wire vocabulary is defined in terms
/// of".
///
/// It is computed rather than curated on purpose. The obvious hand-drawn
/// boundary -- `lib/src/handlers/**` and nothing else -- would have missed the
/// bug that prompted this: `RateLimitOperation` is declared in
/// `lib/src/types/rate_limit_operation.dart`, one import away from the handler
/// that parses it. Any boundary a person draws is a boundary a person has to
/// remember to redraw.
///
/// The set errs broad, and that is the intended direction: being too broad
/// costs a worker rebuild nobody needed, being too narrow costs the 503 above.
/// [normalizeDartSource] takes the sting out of broad by making comment and
/// formatting churn -- most of what actually changes in these files -- not
/// count.
///
/// ## What it does not see
///
/// Only whether a worker was built from the same contract, never whether it is
/// *correct*. And nothing outside `zonai_schema`: a change in the host's own
/// `apps/zonai` message handling that happens not to touch the schema is not
/// in the closure and will not be caught here.
class MessageContractHash {
  MessageContractHash();

  static const _packageName = 'zonai_schema';
  static const _packagePrefix = 'package:$_packageName/';
  static const _handlersDirectory = 'src/handlers';

  /// Directives worth following. `part of` is deliberately not matched: the
  /// token after `part` is `of`, not a quoted URI, so the pattern skips it.
  static final _directive = RegExp(
    '''^\\s*(?:import|export|part)\\s+r?(['"])([^'"]+)\\1''',
    multiLine: true,
  );

  /// The hash of the resolved `zonai_schema` sources, or `null` when there is
  /// nothing to hash -- no package config, no `zonai_schema` in it, or a
  /// resolved copy with no handlers directory (a `zonai_schema` old enough to
  /// predate it). Unknown is not the same as mismatched, and every caller
  /// treats it that way.
  ///
  /// Computed once. Callers stamp up to seven executables per `zonai compile`
  /// and the host reads it on every worker spawn, and the sources cannot
  /// change under a running process in a way this should react to.
  late final String? value = compute();

  /// [value] without the cache, for tests and for callers that genuinely want
  /// to re-read the sources.
  ///
  /// Never throws. This runs on the worker-spawn path, and a staleness check
  /// that takes down the thing it is checking is worse than no check at all --
  /// so anything it cannot answer (a scope missing `fs`/`settings`, a file
  /// that vanished mid-walk, a permission it does not have) becomes "unknown",
  /// which every caller already treats as "not stale". The cost of that choice
  /// is a guard that can go quiet without saying so; see the module docs.
  @visibleForTesting
  String? compute() {
    try {
      return _compute();
    } on Object {
      return null;
    }
  }

  String? _compute() {
    final libRoot = resolveSchemaLibRoot();
    if (libRoot == null) return null;

    final sources = contractFiles(libRoot);
    if (sources.isEmpty) return null;

    // NUL-terminated rather than joined by something readable: a separator
    // that can occur in the content would let a rename be absorbed by the file
    // beside it, so `a.dart` + `bc` and `a.dartb` + `c` would agree. A NUL
    // occurs in neither a path nor [normalizeDartSource]'s output.
    const terminator = '\u0000';
    final buffer = StringBuffer();
    for (final relativePath in sources.keys.toList()..sort()) {
      buffer
        ..write(relativePath)
        ..write(terminator)
        ..write(sources[relativePath])
        ..write(terminator);
    }

    return '${sha256.convert(utf8.encode(buffer.toString()))}';
  }

  /// The nearest `.dart_tool/package_config.json` at or above the project
  /// root, or `null` when there is none.
  ///
  /// Walking up is not defensive padding -- it is the only way this resolves
  /// at all inside a pub workspace, where members share one config at the
  /// workspace root and `apps/playground/.dart_tool/` does not exist. The SDK
  /// finds it by walking up from the entrypoint; anything that wants to know
  /// what a `dart compile exe` will resolve has to walk the same way.
  @visibleForTesting
  String? locatePackageConfig() {
    // `settings.packageConfigPath` is `<projectRoot>/.dart_tool/...`, so two
    // dirnames get back to the root the SDK would start from.
    var directory = fs.path.dirname(
      fs.path.dirname(fs.path.absolute(settings.packageConfigPath)),
    );

    while (true) {
      final candidate = fs.path.join(
        directory,
        '.dart_tool',
        'package_config.json',
      );
      if (fs.file(candidate).existsSync()) return candidate;

      final parent = fs.path.dirname(directory);
      if (parent == directory) return null;
      directory = parent;
    }
  }

  /// The `lib/` directory of the `zonai_schema` the project resolves, or
  /// `null` when the package config cannot answer.
  ///
  /// Deliberately the project's resolution rather than this process's own:
  /// that config is what `dart compile exe` uses for the workers, so it names
  /// the copy a worker is actually built against.
  @visibleForTesting
  String? resolveSchemaLibRoot() {
    final configPath = locatePackageConfig();
    if (configPath == null) return null;

    final Object? decoded;
    try {
      decoded = json.decode(fs.file(configPath).readAsStringSync());
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;

    final packages = decoded['packages'];
    if (packages is! List) return null;

    for (final raw in packages) {
      if (raw is! Map) continue;
      if (raw['name'] != _packageName) continue;

      final rootUri = raw['rootUri'];
      if (rootUri is! String) return null;
      final packageUri = raw['packageUri'];

      // `rootUri` is relative to the directory holding the config, which is
      // what `Uri.resolve` against the config FILE's URI gives. The trailing
      // slash is not cosmetic: without it `Uri.resolve` treats the last
      // segment as a file and `packageUri` replaces it, turning
      // `libs/zonai_schema` + `lib/` into `libs/lib/`.
      final base = fs.path.toUri(fs.path.absolute(configPath));
      final root = base.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
      final lib = root.resolve(packageUri is String ? packageUri : 'lib/');

      // `fs.path.fromUri`, not `Uri.toFilePath()`: the latter reads
      // `Platform.isWindows` and knows nothing about the filesystem this is
      // configured with, so on a Windows host it handed a `\`-separated path
      // back into an `fs` whose context is posix -- every later `join` then
      // pointed at a directory that does not exist, and the contract hash
      // came out null.
      return fs.path.normalize(fs.path.fromUri(lib));
    }

    return null;
  }

  /// Every hashed file under [libRoot], keyed by its path relative to
  /// [libRoot] (so the hash does not move when the package does -- a pub-cache
  /// copy and a path dependency of the same sources agree) and valued by its
  /// normalized source.
  @visibleForTesting
  Map<String, String> contractFiles(String libRoot) {
    final handlers = fs.directory(fs.path.join(libRoot, _handlersDirectory));
    if (!handlers.existsSync()) return const {};

    final pending = <String>[
      for (final entity in handlers.listSync(recursive: true))
        if (entity is File && fs.path.extension(entity.path) == '.dart')
          fs.path.normalize(entity.absolute.path),
    ];

    final sources = <String, String>{};
    final visited = <String>{};

    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!visited.add(path)) continue;

      final file = fs.file(path);
      if (!file.existsSync()) continue;

      final source = file.readAsStringSync();
      sources[fs.path.relative(path, from: libRoot)] = normalizeDartSource(
        source,
      );

      for (final match in _directive.allMatches(source)) {
        final target = _resolveDirective(
          match.group(2)!,
          from: path,
          libRoot: libRoot,
        );
        if (target != null) pending.add(target);
      }
    }

    return sources;
  }

  /// The absolute path a directive URI points at, or `null` when it leaves the
  /// package -- `dart:` and third-party `package:` imports are somebody else's
  /// contract, and a relative path that climbs out of [libRoot] is not one of
  /// ours to hash.
  String? _resolveDirective(
    String uri, {
    required String from,
    required String libRoot,
  }) {
    final String candidate;
    if (uri.startsWith(_packagePrefix)) {
      candidate = fs.path.join(libRoot, uri.substring(_packagePrefix.length));
    } else if (uri.startsWith('dart:') || uri.startsWith('package:')) {
      return null;
    } else {
      candidate = fs.path.join(fs.path.dirname(from), uri);
    }

    final normalized = fs.path.normalize(candidate);
    if (!fs.path.isWithin(libRoot, normalized)) return null;
    return normalized;
  }
}
