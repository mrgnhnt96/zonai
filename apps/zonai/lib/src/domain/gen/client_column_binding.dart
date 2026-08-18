import 'package:zonai_schema/src/types/column_shape_kind.dart';
import 'package:zonai_schema/src/types/schema_shape.dart';

import 'client_names.dart';

/// One column on the WRITE side: create and update.
///
/// A separate resolution from [ColumnBinding], because the two disagree in
/// three places and every one of them is load-bearing:
///
///  - **Secret columns are writable.** `_sanitizeRows` strips a password from
///    every response, so [ColumnBinding] correctly returns null for it -- but
///    `_requireFilterableColumn` is the *only* place the server special-cases a
///    secret, and it guards filters, not writes. A create builder without the
///    password field cannot create a row on a table that requires one.
///  - **Photo columns invert.** The row reads `Uri`; the write takes a
///    `PhotoId`, which `_verifyPhotoIds` checks against the `_photos` table.
///  - **Read-only columns vanish.** `createdAt`, `updatedAt` and anything
///    behind a `ServerGeneratedTransformer` are set by the server.
final class WriteBinding {
  const WriteBinding({
    required this.column,
    required this.field,
    required this.type,
    required this.patch,
    required this.isRequiredOnCreate,
  });

  final ColumnShape column;

  /// Dart field name. `author_id` -> `authorId`.
  final String field;

  /// The value type this column accepts, never nullable -- absence is spelled
  /// by omitting the field, and NULL by `Field.clear()`.
  final String type;

  /// The `Patch` subclass gating this column's operation vocabulary.
  final String patch;

  /// Whether a create call must supply it.
  final bool isRequiredOnCreate;

  String get wireKey => column.name;

  /// The writable columns of [shape], in declaration order.
  static List<WriteBinding> forTable(
    TableSchemaShape shape, {
    required ClientNameTable names,
  }) {
    return [
      for (final column in shape.columns)
        if (forColumn(column, table: shape.table, names: names)
            case final binding?)
          binding,
    ];
  }

  /// Resolves one column, or null when it cannot be written.
  static WriteBinding? forColumn(
    ColumnShape column, {
    required String table,
    required ClientNameTable names,
  }) {
    // Set by the server, not by the caller.
    //
    // Checked by kind as well as by the flag: a `createdAt` column is
    // server-managed by definition, and a shape that arrived without
    // `isReadOnly` set would otherwise mint a writable `created_at` whose
    // value the server overwrites anyway.
    if (column.isReadOnly) return null;
    if (column.kind == ColumnShapeKind.createdAt ||
        column.kind == ColumnShapeKind.updatedAt) {
      return null;
    }

    // `Literal.toJson` runs `jsonEncode`, which throws on a `BigInt` -- so a
    // typed setter for one would be a compile-time promise the request cannot
    // keep. Measured, not assumed; the same finding excludes it from
    // `isTokenable`.
    if (column.kind == ColumnShapeKind.bigInt) return null;

    final (type, patch) = _bindWrite(column, table: table, names: names);

    // The id is generated when absent (`IdTransformer` carries a `generate`
    // and mixes in `CreatePrimaryKey`), and a column with a default does not
    // need one either.
    final generated = column.isPrimaryKey && column.kind == ColumnShapeKind.id;
    final required =
        !column.isNullable &&
        !generated &&
        !column.autoIncrement &&
        column.defaultValue == null;

    return WriteBinding(
      column: column,
      field: ColumnBinding.fieldName(column.name),
      type: type,
      patch: patch,
      isRequiredOnCreate: required,
    );
  }

  /// The write-side Dart type and the `Patch` subclass that gates it.
  static (String, String) _bindWrite(
    ColumnShape column, {
    required String table,
    required ClientNameTable names,
  }) {
    return switch (column.kind) {
      // The inversion: an id in, a URL out.
      ColumnShapeKind.photo => ('PhotoId', 'Field'),
      ColumnShapeKind.photos => ('List<PhotoId>', 'ListField'),
      ColumnShapeKind.id => (
        ColumnBinding.idType(column, table: table, names: names),
        'Field',
      ),
      ColumnShapeKind.integer => ('int', 'NumField'),
      ColumnShapeKind.real => ('double', 'NumField'),
      ColumnShapeKind.list => ('List<Object?>', 'ListField'),
      ColumnShapeKind.enumList => ('List<String>', 'ListField'),
      ColumnShapeKind.map => ('Map<String, Object?>', 'MapField'),
      ColumnShapeKind.boolean ||
      ColumnShapeKind.isVerified => ('bool', 'Field'),
      ColumnShapeKind.dateTime ||
      ColumnShapeKind.createdAt ||
      ColumnShapeKind.updatedAt => ('DateTime', 'Field'),
      ColumnShapeKind.blob => ('List<int>', 'Field'),
      ColumnShapeKind.text ||
      ColumnShapeKind.email ||
      ColumnShapeKind.password ||
      ColumnShapeKind.deviceToken ||
      ColumnShapeKind.enum_ => ('String', 'Field'),
      // Excluded above; the switch stays exhaustive so a new kind is a
      // compile error here rather than a silent `Field<Object?>`.
      ColumnShapeKind.bigInt => ('BigInt', 'Field'),
    };
  }

  /// The generic argument for this column's `Patch`.
  ///
  /// `ListField` is already `Patch<List<E>>`, so it takes the ELEMENT type
  /// while everything else takes the value type.
  String get patchType => switch (patch) {
    'ListField' => _elementOf(type),
    _ => type,
  };

  static String _elementOf(String listType) {
    final open = listType.indexOf('<');
    if (open == -1 || !listType.endsWith('>')) return 'Object?';
    return listType.substring(open + 1, listType.length - 1);
  }
}

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
        idType(column, table: table, names: names),
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

    final type = idType(column, table: table, names: names);
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
  static String idType(
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
