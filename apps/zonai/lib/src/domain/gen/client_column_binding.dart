import 'package:zonai_schema/src/types/column_shape_kind.dart';
import 'package:zonai_schema/src/types/schema_shape.dart';

import 'client_names.dart';

/// One column, resolved to the Dart it turns into.
///
/// The whole of §4.1 lives here: rows come off the wire as **raw SQLite
/// storage values**, because `_list` returns `result.rows.map((e) => e.toMap())`
/// untouched and `_sanitizeRows` only strips secrets and rewrites photos. So a
/// `dateTime` arrives as an epoch-millisecond `int`, a `boolean` as `0`/`1`,
/// and `list` / `map` / `enumList` as JSON-encoded `String`s. Decoding those
/// correctly is most of what a generated read model is worth.
final class ColumnBinding {
  const ColumnBinding({
    required this.column,
    required this.field,
    required this.type,
    required this.parseExpression,
    required this.isNullable,
  });

  final ColumnShape column;

  /// Dart field name. `author_id` → `authorId`; the wire key stays snake_case.
  final String field;

  /// Dart type, `?`-suffixed when nullable.
  final String type;

  /// The `fromJson` right-hand side, reading through the shared reader.
  final String parseExpression;

  final bool isNullable;

  /// Wire key. `fromJson` reads `json['author_id']`, per §5.2.
  String get wireKey => column.name;

  /// Resolves one column, or null when it should not appear on the model.
  ///
  /// Secret columns return null rather than a nullable field: §4.4 --
  /// `_sanitizeRows` strips them from **every** response, so a field for one
  /// would be null in every row that ever parses. Absent is the honest model.
  static ColumnBinding? forColumn(
    ColumnShape column, {
    required String table,
    required ClientNameTable names,
  }) {
    if (column.isSecret) return null;

    final (type, reader) = _bind(column, table: table, names: names);
    final nullable = column.isNullable;
    final call =
        "_r.${nullable ? '${reader}OrNull' : reader}"
        "(json, '${column.name}', kind: '${column.kind.toJson()}')";

    return ColumnBinding(
      column: column,
      field: fieldName(column.name),
      type: nullable ? '$type?' : type,
      parseExpression: _wrap(column, call, table: table, names: names),
      isNullable: nullable,
    );
  }

  /// Whether a `ColumnRef` may be minted for this column kind.
  ///
  /// A token is a promise: *if it compiles, it works*. That promise only holds
  /// where the decoded Dart value is also the correct value to filter **by**,
  /// and for seven kinds it is not. Each was checked by running the real
  /// serializers in `where_value.dart`, not by reading them:
  ///
  /// | Kind | `.eq(decodedValue)` does |
  /// | --- | --- |
  /// | `bigInt` | **throws** `JsonUnsupportedObjectError` -- neither `whereValueToJsonEncodable` nor `whereValueToParam` handles `BigInt`, so `jsonEncode` rejects it at request time, every time |
  /// | `list`, `enumList`, `map` | serializes to a JSON *structure*, but the column stores a JSON-encoded **String** -- so it matches nothing, and the SQL parameter is a `List`/`Map` the driver cannot bind |
  /// | `blob` | same, as a `List<int>` |
  /// | `photo`, `photos` | the column stores a photo **id** (`_verifyPhotoIds` enforces exactly that) and `_resolvePhotoFields` rewrites it to a URL on read, so a token typed `Uri` builds a filter against a value that was never stored |
  ///
  /// For the kinds that remain, §4.5 holds and holds *because it was measured*:
  /// `DateTime` normalizes to epoch-ms on the wire and as a bound parameter,
  /// `bool` to `0`/`1` as a parameter, and an extension-type id erases to its
  /// `String`. Those pass straight through with no work.
  ///
  /// Emitting a token for the other seven would be worse than emitting none:
  /// it makes a filter that cannot work *look* type-checked, which is the exact
  /// failure this surface exists to prevent. They arrive when each has a type
  /// that is honest about the wire -- `PhotoId` for a photo, alongside the
  /// write builders.
  static bool isTokenable(ColumnShapeKind kind) => switch (kind) {
    ColumnShapeKind.id ||
    ColumnShapeKind.text ||
    ColumnShapeKind.email ||
    ColumnShapeKind.deviceToken ||
    ColumnShapeKind.enum_ ||
    ColumnShapeKind.integer ||
    ColumnShapeKind.real ||
    ColumnShapeKind.boolean ||
    ColumnShapeKind.isVerified ||
    ColumnShapeKind.dateTime ||
    ColumnShapeKind.createdAt ||
    ColumnShapeKind.updatedAt => true,
    // A `password` column is a SecretTransformer and never reaches here --
    // `forColumn` already returned null for it.
    ColumnShapeKind.password ||
    ColumnShapeKind.bigInt ||
    ColumnShapeKind.list ||
    ColumnShapeKind.enumList ||
    ColumnShapeKind.map ||
    ColumnShapeKind.blob ||
    ColumnShapeKind.photo ||
    ColumnShapeKind.photos => false,
  };

  /// `author_id` → `authorId`, `created_at` → `createdAt`.
  static String fieldName(String column) {
    final parts = column
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return column;
    return [
      parts.first,
      for (final part in parts.skip(1))
        part[0].toUpperCase() + part.substring(1),
    ].join();
  }

  /// The Dart type and the shared-runtime reader method for [column].
  static (String, String) _bind(
    ColumnShape column, {
    required String table,
    required ClientNameTable names,
  }) {
    return switch (column.kind) {
      // §4.2: photo columns are asymmetric -- `_resolvePhotoFields` rewrites
      // the stored id into a fully-qualified URL on the way out, while the
      // write path wants the id back. Phase 1 is read-only, so: `Uri`.
      ColumnShapeKind.photo => ('Uri', 'uri'),
      ColumnShapeKind.photos => ('List<Uri>', 'uriList'),
      ColumnShapeKind.id => (
        _idType(column, table: table, names: names),
        'string',
      ),
      ColumnShapeKind.text ||
      ColumnShapeKind.email ||
      ColumnShapeKind.password ||
      ColumnShapeKind.deviceToken ||
      // Phase 4 turns this into a real Dart enum. A `String` here is not a
      // placeholder: the server may add a member without breaking an older
      // client, and a generated enum would make that a parse failure.
      ColumnShapeKind.enum_ => ('String', 'string'),
      ColumnShapeKind.integer => ('int', 'integer'),
      ColumnShapeKind.real => ('double', 'real'),
      ColumnShapeKind.boolean ||
      ColumnShapeKind.isVerified => ('bool', 'boolean'),
      ColumnShapeKind.bigInt => ('BigInt', 'bigInt'),
      ColumnShapeKind.dateTime ||
      ColumnShapeKind.createdAt ||
      ColumnShapeKind.updatedAt => ('DateTime', 'dateTime'),
      ColumnShapeKind.enumList => ('List<String>', 'stringList'),
      ColumnShapeKind.list => ('List<Object?>', 'list'),
      ColumnShapeKind.map => ('Map<String, Object?>', 'map'),
      ColumnShapeKind.blob => ('List<int>', 'bytes'),
    };
  }

  /// Wraps the reader call in the id constructor, when the column has one.
  static String _wrap(
    ColumnShape column,
    String call, {
    required String table,
    required ClientNameTable names,
  }) {
    if (column.kind != ColumnShapeKind.id) return call;

    final type = _idType(column, table: table, names: names);
    if (type == 'String') return call;

    return column.isNullable
        ? 'switch ($call) { final value? => $type(value), _ => null }'
        : '$type($call)';
  }

  /// Which id type a `kind: id` column carries.
  ///
  /// `ForeignKeyShape` gives `author_id → authors.id`, so `PostsRow.authorId`
  /// is an `AuthorsId` and passing a `PostsId` there stops compiling -- for
  /// free, from data the server already publishes. A foreign key into a table
  /// this run did not emit (every `_`-prefixed one) has no type to name, so it
  /// falls back to the `String` it erases to anyway (§4.5).
  static String _idType(
    ColumnShape column, {
    required String table,
    required ClientNameTable names,
  }) {
    if (column.foreignKey case final fk?) {
      return names[fk.table]?.id ?? 'String';
    }
    if (column.isPrimaryKey) {
      return names[table]?.id ?? 'String';
    }
    return 'String';
  }
}

/// One expandable relation: `row.expanded?.authorId`.
///
/// §4.3 -- `_expandRecord` writes related rows to `row['expanded'][<fk column>]`,
/// keyed by the **foreign-key column name**, and the key is absent entirely
/// when nothing was expanded.
final class ExpandBinding {
  const ExpandBinding({
    required this.field,
    required this.wireKey,
    required this.rowType,
    required this.targetTable,
  });

  final String field;
  final String wireKey;
  final String rowType;
  final String targetTable;

  /// The expandable columns of [shape], in declaration order.
  ///
  /// A photo column has a foreign key into `_photos` but expanding it would
  /// yield a framework-internal row, so it is not one of these.
  static List<ExpandBinding> forTable(
    TableSchemaShape shape, {
    required ClientNameTable names,
  }) {
    return [
      for (final column in shape.columns)
        if (!column.isSecret &&
            column.kind != ColumnShapeKind.photo &&
            column.kind != ColumnShapeKind.photos)
          if (column.foreignKey case final fk?)
            if (names[fk.table] case final target?)
              ExpandBinding(
                field: ColumnBinding.fieldName(column.name),
                wireKey: column.name,
                rowType: target.row,
                targetTable: fk.table,
              ),
    ];
  }
}
