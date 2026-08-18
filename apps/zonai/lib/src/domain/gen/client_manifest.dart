import 'dart:convert';

/// The record of what `zonai gen client` wrote, kept inside the output
/// directory.
///
/// This is the whole write guard. The natural output path — `../app/lib/gen/
/// zonai` — is outside the server repo *by construction*, so a guard keyed on
/// location would refuse the primary use case and its opt-out would become
/// boilerplate nobody reads. Provenance answers the question that actually
/// matters: did *we* write what is already here?
///
/// Consequences, all of them deliberate:
///
/// * An empty or missing directory is fair game.
/// * A directory carrying a manifest is ours; its listed files may be
///   rewritten or removed.
/// * A non-empty directory with no manifest is somebody else's — refuse,
///   unless the caller says `--force`.
/// * A file that is not in the manifest is never touched, `--force` included.
///   Forcing grants permission to *add*, not to delete.
final class ClientManifest {
  const ClientManifest({
    required this.generatorVersion,
    required this.schemaHash,
    required this.files,
  });

  /// Lives inside the output directory. Named, not hidden: a human who opens
  /// the generated directory should be able to see why it is off limits.
  static const fileName = 'zonai_client_manifest.json';

  static const formatVersion = 1;

  static const _encoder = JsonEncoder.withIndent('  ');

  /// The `zonai` version that wrote these files.
  final String generatorVersion;

  /// The schema hash the files were generated from — the same value
  /// `.zonai/schema.json` carries.
  final String schemaHash;

  /// Paths relative to the output directory, posix separators, sorted.
  ///
  /// Does not include [fileName] itself; the manifest is implicitly ours.
  final List<String> files;

  factory ClientManifest.fromJson(Map<String, dynamic> json) {
    return ClientManifest(
      generatorVersion: switch (json['generatorVersion']) {
        final String value => value,
        _ => 'unknown',
      },
      schemaHash: switch (json['schemaHash']) {
        final String value => value,
        _ => '',
      },
      files: switch (json['files']) {
        final List<dynamic> value => [
          for (final entry in value)
            if (entry case final String path) path,
        ]..sort(),
        _ => const [],
      },
    );
  }

  /// Parses the on-disk manifest, or null when it is absent or unreadable.
  ///
  /// Unreadable counts as "not a manifest": a corrupt file must not be taken
  /// as a licence to overwrite the directory it sits in.
  static ClientManifest? tryParse(String contents) {
    try {
      final json = jsonDecode(contents);
      if (json is! Map<String, dynamic>) return null;
      return ClientManifest.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'generatorVersion': generatorVersion,
    'schemaHash': schemaHash,
    'files': files,
  };

  String encode() => '${_encoder.convert(toJson())}\n';

  /// Files this manifest owns that [next] does not — the ones regeneration
  /// should delete, and the only ones it is ever allowed to.
  List<String> staleAgainst(ClientManifest next) {
    final kept = next.files.toSet();
    return [
      for (final file in files)
        if (!kept.contains(file)) file,
    ];
  }
}
