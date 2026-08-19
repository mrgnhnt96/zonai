import 'package:zonai_schema/src/types/schema_shape.dart';

import '../../deps/fs.dart';
import 'client_emitter.dart';
import 'client_manifest.dart';
import 'dart_client_emitter.dart';
import 'client_schema_document.dart';
import 'client_settings.dart';

/// What one generation run would produce, before anything touches disk.
///
/// Building the whole run as a value is what lets `--check` reuse the exact
/// code path `zonai gen client` writes with. A checker that regenerated
/// differently would eventually disagree with the generator about what "stale"
/// means, and the disagreement would surface as a CI failure nobody could
/// reproduce locally.
final class ClientGenerationPlan {
  const ClientGenerationPlan({
    required this.schema,
    required this.schemaFileContents,
    required this.files,
    required this.manifest,
    required this.outputDirectory,
    required this.schemaFilePath,
  });

  final ClientSchemaDocument schema;

  /// The bytes destined for `.zonai/schema.json`.
  final String schemaFileContents;

  /// Generated file contents, keyed by path relative to [outputDirectory].
  final Map<String, String> files;

  final ClientManifest manifest;
  final String outputDirectory;
  final String schemaFilePath;
}

/// One difference between a plan and what is on disk.
final class ClientDrift {
  const ClientDrift(this.kind, this.path, [this.detail]);

  final ClientDriftKind kind;

  /// Path as a human would type it, relative to the project.
  final String path;

  final String? detail;

  @override
  String toString() {
    final marker = switch (kind) {
      ClientDriftKind.missing => '+',
      ClientDriftKind.changed => '~',
      ClientDriftKind.extra => '-',
    };
    final suffix = detail == null ? '' : ' -- $detail';
    return '  $marker $path${_label()}$suffix';
  }

  String _label() => switch (kind) {
    ClientDriftKind.missing => ' (missing)',
    ClientDriftKind.changed => ' (differs)',
    ClientDriftKind.extra => ' (no longer generated)',
  };
}

enum ClientDriftKind { missing, changed, extra }

/// Why a write into [directory] was refused.
final class ClientWriteRefusal {
  const ClientWriteRefusal({required this.directory, required this.entries});

  final String directory;

  /// A sample of what is already there, so the message can show its work.
  final List<String> entries;

  String get message {
    final sample = entries.take(5).join(', ');
    final more = entries.length > 5 ? ', and ${entries.length - 5} more' : '';
    return '''
Refusing to generate into $directory: it already has files and no
${ClientManifest.fileName}, so zonai did not write what is there.

  contains: $sample$more

Point `client.output` in zonai.yaml at a directory zonai owns, or pass --force
to write into this one anyway. --force only adds files; it never deletes
anything zonai did not generate.''';
  }
}

/// Plans, writes and verifies the generated client.
///
/// Deliberately unaware of how a client is *emitted* — [emitter] decides that.
/// Everything here is provenance, determinism and drift, which are the parts
/// that have to be right before an emitter is worth writing.
final class ClientGenerator {
  const ClientGenerator({
    required this.settings,
    required this.outputDirectory,
    required this.schemaFilePath,
    required this.generatorVersion,
    this.emitter = const DartClientEmitter(),
  });

  final ClientSettings settings;

  /// Resolved output directory — `--output` when given, `client.output`
  /// otherwise.
  final String outputDirectory;

  /// Where `.zonai/schema.json` lives.
  final String schemaFilePath;

  final String generatorVersion;
  final ClientEmitter emitter;

  /// Turns live schema shapes into a full plan. Touches nothing.
  ClientGenerationPlan plan(Map<String, TableSchemaShape> shapes) {
    // Everything the config leaves out, not just what it names: the
    // `_`-prefixed system tables are excluded by default and `tables.include`
    // is what brings one back. Filtering here rather than in the emitter keeps
    // `.zonai/schema.json` exactly the generator's input, so its hash moves
    // when the generated client would and stays put when it would not.
    final schema = ClientSchemaDocument.fromShapes(
      shapes,
      excludeTables: settings.excludedFrom(shapes.keys),
    );

    final emitted = emitter.emit(
      ClientGenerationInput(
        schema: schema,
        settings: settings,
        generatorVersion: generatorVersion,
      ),
    );

    final names = emitted.keys.toList()..sort();
    final files = {for (final name in names) name: emitted[name]!};

    return ClientGenerationPlan(
      schema: schema,
      schemaFileContents: schema.encode(),
      files: files,
      manifest: ClientManifest(
        generatorVersion: generatorVersion,
        schemaHash: schema.hash,
        files: names,
      ),
      outputDirectory: outputDirectory,
      schemaFilePath: schemaFilePath,
    );
  }

  /// The manifest already in [outputDirectory], or null when there is none.
  ClientManifest? readManifest() {
    final file = fs.file(
      fs.path.join(outputDirectory, ClientManifest.fileName),
    );
    if (!file.existsSync()) return null;
    return ClientManifest.tryParse(file.readAsStringSync());
  }

  /// The write guard. Returns null when writing is allowed.
  ///
  /// Refuses exactly one situation: a non-empty directory zonai has no record
  /// of writing. Empty, absent, and already-ours all pass.
  ClientWriteRefusal? guard({bool force = false}) {
    if (force) return null;

    final directory = fs.directory(outputDirectory);
    if (!directory.existsSync()) return null;

    // `.DS_Store` is not evidence of hand-written code; refusing on it would
    // make the guard fire on macOS for directories that are effectively
    // empty, and a guard that cries wolf is one people learn to --force past.
    final entries =
        directory
            .listSync()
            .map((entity) => fs.path.basename(entity.path))
            .where((name) => name != '.DS_Store')
            .toList()
          ..sort();

    if (entries.isEmpty) return null;
    if (entries.contains(ClientManifest.fileName)) return null;

    return ClientWriteRefusal(directory: outputDirectory, entries: entries);
  }

  /// Applies [plan], returning the paths written and removed.
  ///
  /// Removal is bounded by the *previous* manifest: a file zonai did not write
  /// is never deleted, whatever `--force` says.
  ({List<String> written, List<String> removed}) write(
    ClientGenerationPlan plan,
  ) {
    final previous = readManifest();

    final schemaFile = fs.file(plan.schemaFilePath);
    schemaFile.parent.createSync(recursive: true);
    schemaFile.writeAsStringSync(plan.schemaFileContents);

    final directory = fs.directory(plan.outputDirectory);
    directory.createSync(recursive: true);

    final written = <String>[plan.schemaFilePath];
    for (final entry in plan.files.entries) {
      final file = fs.file(fs.path.join(plan.outputDirectory, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      written.add(file.path);
    }

    fs
        .file(fs.path.join(plan.outputDirectory, ClientManifest.fileName))
        .writeAsStringSync(plan.manifest.encode());

    final removed = <String>[];
    for (final stale in previous?.staleAgainst(plan.manifest) ?? const []) {
      final file = fs.file(fs.path.join(plan.outputDirectory, stale));
      if (!file.existsSync()) continue;
      file.deleteSync();
      removed.add(file.path);
    }

    return (written: written, removed: removed);
  }

  /// Compares [plan] against disk without writing anything.
  ///
  /// An empty result means the committed output is current.
  List<ClientDrift> check(ClientGenerationPlan plan) {
    final drift = <ClientDrift>[];

    final schemaFile = fs.file(plan.schemaFilePath);
    if (!schemaFile.existsSync()) {
      drift.add(ClientDrift(.missing, plan.schemaFilePath));
    } else {
      final onDisk = ClientSchemaDocument.tryParse(
        schemaFile.readAsStringSync(),
      );
      if (onDisk == null) {
        drift.add(ClientDrift(.changed, plan.schemaFilePath, 'unreadable'));
      } else if (onDisk.hash != plan.schema.hash) {
        drift.add(
          ClientDrift(
            .changed,
            plan.schemaFilePath,
            'schema hash ${_short(onDisk.hash)} -> ${_short(plan.schema.hash)}',
          ),
        );
      }
    }

    for (final entry in plan.files.entries) {
      final path = fs.path.join(plan.outputDirectory, entry.key);
      final file = fs.file(path);
      if (!file.existsSync()) {
        drift.add(ClientDrift(.missing, path));
        continue;
      }
      if (_sameContent(file.readAsStringSync(), entry.value)) continue;
      drift.add(ClientDrift(.changed, path));
    }

    // Files a previous run generated that this one would not: real drift, and
    // the kind a content comparison alone would miss entirely.
    for (final stale
        in readManifest()?.staleAgainst(plan.manifest) ?? const <String>[]) {
      final path = fs.path.join(plan.outputDirectory, stale);
      if (fs.file(path).existsSync()) {
        drift.add(ClientDrift(.extra, path));
      }
    }

    return drift;
  }

  /// Compares generated content while ignoring the one difference version
  /// control is entitled to introduce: the line ending.
  ///
  /// The emitter writes `\n` on every platform, deliberately, so the output is
  /// byte-identical wherever it runs. Git is not obliged to leave it that way.
  /// Git for Windows installs with `core.autocrlf=true`, which rewrites text
  /// files to CRLF on checkout -- so a Windows user who commits a generated
  /// client gets CRLF back in their working tree, and a raw `!=` against
  /// freshly emitted LF reports EVERY file as drifted. `--check` then fails on
  /// a correct, up-to-date client and there is nothing the user can do to it
  /// that helps: regenerating rewrites LF, and the next checkout undoes it.
  ///
  /// Measured 2026-08-19, where it showed up first as the repo's own goldens
  /// failing on `windows-latest` with `'...BY HAND\n'` against
  /// `'...BY HAND\r\n'`. That half is fixed by `.gitattributes`; this half is
  /// not, because a consumer's repository is not ours to configure.
  ///
  /// Line endings are the ONLY thing forgiven. Everything else -- whitespace,
  /// ordering, a single changed character -- is still drift, because for
  /// generated code it means the generator would write something different.
  static bool _sameContent(String onDisk, String generated) =>
      _lf(onDisk) == _lf(generated);

  static String _lf(String content) => content.replaceAll('\r\n', '\n');

  static String _short(String hash) =>
      hash.length <= 12 ? hash : hash.substring(0, 12);
}
