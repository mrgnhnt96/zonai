import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:zonai_schema/src/types/schema_shape.dart';

/// `.zonai/schema.json` — the typed client generator's entire input.
///
/// Serialization is delegated to [TableSchemaShape.toJson] / [ColumnShape]
/// rather than re-encoded here: a second encoding of the same shapes would
/// drift silently the first time a column property was added.
///
/// Two properties this file has to hold, because the rest of the feature rests
/// on them:
///
/// * **Deterministic.** Same schema ⇒ byte-identical file. Table keys are
///   sorted; columns are emphatically *not* — column order is declaration
///   order, and sorting it would reorder every generated constructor (see the
///   index-order trap in `docs/known-issues.md`).
/// * **Self-describing.** [hash] covers the tables and nothing else, so it can
///   live inside the file it describes without chasing its own tail. That hash
///   is what `--check` compares.
final class ClientSchemaDocument {
  const ClientSchemaDocument({required this.tables, required this.hash});

  /// Bumped when the on-disk layout changes in a way a reader must notice.
  static const formatVersion = 1;

  static const _encoder = JsonEncoder.withIndent('  ');

  /// Table shapes, in sorted key order.
  final Map<String, TableSchemaShape> tables;

  /// SHA-256 over the canonical encoding of [tables].
  final String hash;

  /// Builds the document from live shapes, dropping anything [excludeTables]
  /// names.
  factory ClientSchemaDocument.fromShapes(
    Map<String, TableSchemaShape> shapes, {
    Iterable<String> excludeTables = const [],
  }) {
    final excluded = excludeTables.toSet();
    final names = shapes.keys.where((name) => !excluded.contains(name)).toList()
      ..sort();

    final tables = {for (final name in names) name: shapes[name]!};

    return ClientSchemaDocument(tables: tables, hash: _hashOf(tables));
  }

  factory ClientSchemaDocument.fromJson(Map<String, dynamic> json) {
    final raw = switch (json['tables']) {
      final Map<String, dynamic> value => value,
      final value => throw FormatException(
        'Invalid schema.json: `tables` was $value, expected a map.',
      ),
    };

    final names = raw.keys.toList()..sort();
    final tables = {
      for (final name in names)
        name: TableSchemaShape.fromJson(
          Map<String, dynamic>.from(raw[name] as Map),
        ),
    };

    return ClientSchemaDocument(
      tables: tables,
      // Recomputed rather than trusted: a hand-edited `hash` that disagreed
      // with the tables beside it would make `--check` pass on drift, which
      // is the one thing this file exists to catch.
      hash: _hashOf(tables),
    );
  }

  /// Parses the on-disk form, or returns null when [contents] is not a
  /// schema.json this version understands.
  static ClientSchemaDocument? tryParse(String contents) {
    try {
      final json = jsonDecode(contents);
      if (json is! Map<String, dynamic>) return null;
      return ClientSchemaDocument.fromJson(json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static String _hashOf(Map<String, TableSchemaShape> tables) {
    final canonical = jsonEncode({
      for (final entry in tables.entries) entry.key: entry.value.toJson(),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'hash': hash,
    'tables': {
      for (final entry in tables.entries) entry.key: entry.value.toJson(),
    },
  };

  /// The exact bytes to write to `.zonai/schema.json`.
  ///
  /// Indented and newline-terminated so a schema change shows up as a handful
  /// of changed lines in review rather than one very long one.
  String encode() => '${_encoder.convert(toJson())}\n';

  @override
  bool operator ==(Object other) =>
      other is ClientSchemaDocument && hash == other.hash;

  @override
  int get hashCode => hash.hashCode;
}
