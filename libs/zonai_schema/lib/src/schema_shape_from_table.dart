import 'package:raindrop/raindrop.dart' as rd;
import 'package:raindrop_sqlite/raindrop_sqlite.dart'
    show BigIntTransformer, BooleanTransfomer, DateTimeTransfomer;
import 'package:zonai_schema/src/column_types/created_at_column.dart';
import 'package:zonai_schema/src/column_types/email_column.dart';
import 'package:zonai_schema/src/column_types/enum_column.dart';
import 'package:zonai_schema/src/column_types/enum_list_column.dart';
import 'package:zonai_schema/src/column_types/id_column.dart';
import 'package:zonai_schema/src/column_types/is_verified_column.dart';
import 'package:zonai_schema/src/column_types/list_column.dart';
import 'package:zonai_schema/src/column_types/map_column.dart';
import 'package:zonai_schema/src/column_types/password_column.dart';
import 'package:zonai_schema/src/column_types/photo_column.dart';
import 'package:zonai_schema/src/column_types/photos_column.dart';
import 'package:zonai_schema/src/column_types/updated_at_column.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';
import 'package:zonai_schema/src/transformers/server_generated_transformer.dart';
import 'package:zonai_schema/src/types/column_shape_kind.dart';
import 'package:zonai_schema/src/types/schema_shape.dart';

/// Builds [TableSchemaShape] from a Raindrop [table] definition.
TableSchemaShape tableSchemaShapeFromTable(rd.Table table, {bool isView = false}) {
  return TableSchemaShape(
    table: table.name,
    columns: [
      for (final column in table.columns) columnShapeFromColumn(column),
    ],
    isView: isView,
  );
}

ColumnShape columnShapeFromColumn(rd.Column column) {
  final fkRef = column.foreignKeyReference;
  final foreignKey = fkRef == null
      ? null
      : ForeignKeyShape(
          table: fkRef.referencedTable,
          column: fkRef.referencedColumnName,
        );

  final (:kind, :enumValues, :isSecret, :isReadOnly) = _describeColumn(column);

  return ColumnShape(
    name: column.name,
    kind: kind,
    isNullable: column.isNullable,
    isPrimaryKey: column.isPrimaryKey,
    autoIncrement: column.autoIncrement,
    sqlType: column.sqlType ?? 'TEXT',
    defaultValue: column.defaultValue,
    foreignKey: foreignKey,
    enumValues: enumValues,
    isSecret: isSecret,
    isReadOnly: isReadOnly,
  );
}

({
  ColumnShapeKind kind,
  List<String> enumValues,
  bool isSecret,
  bool isReadOnly,
})
_describeColumn(rd.Column column) {
  return switch (column.transformer) {
    PhotoTransformer() => (
      kind: .photo,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    PhotosTransformer() => (
      kind: .photos,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    EmailTransformer() => (
      kind: .email,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    PasswordTransformer() => (
      kind: .password,
      enumValues: const [],
      isSecret: true,
      isReadOnly: false,
    ),
    IdTransformer() => (
      kind: .id,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    IsVerifiedTransformer() => (
      kind: .isVerified,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    CreatedAtTransformer() => (
      kind: .createdAt,
      enumValues: const [],
      isSecret: false,
      isReadOnly: true,
    ),
    UpdatedAtTransformer() => (
      kind: .updatedAt,
      enumValues: const [],
      isSecret: false,
      isReadOnly: true,
    ),
    EnumTransformer(:final values) => (
      kind: .enum_,
      enumValues: [for (final value in values) value.name],
      isSecret: false,
      isReadOnly: false,
    ),
    EnumListTransformer(:final values) => (
      kind: .enumList,
      enumValues: [for (final value in values) value.name],
      isSecret: false,
      isReadOnly: false,
    ),
    MapTransformer() => (
      kind: .map,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    ListTransformer() => (
      kind: .list,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    BooleanTransfomer() => (
      kind: .boolean,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    DateTimeTransfomer() => (
      kind: .dateTime,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    BigIntTransformer() => (
      kind: .bigInt,
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    final transformer when transformer is SecretTransformer => (
      kind: _kindFromSqlType(column.sqlType),
      enumValues: const [],
      isSecret: true,
      isReadOnly: false,
    ),
    final transformer when transformer is ServerGeneratedTransformer => (
      kind: _kindFromSqlType(column.sqlType),
      enumValues: const [],
      isSecret: false,
      isReadOnly: true,
    ),
    null => (
      kind: _kindFromSqlType(column.sqlType),
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
    _ => (
      kind: _kindFromTransformerRuntimeType(column),
      enumValues: const [],
      isSecret: false,
      isReadOnly: false,
    ),
  };
}

/// Fallback when [ColumnShapeKind] pattern matching misses a transformer type
/// (e.g. duplicate class across Raindrop packages).
ColumnShapeKind _kindFromTransformerRuntimeType(rd.Column column) {
  return switch (column.transformer?.runtimeType.toString()) {
    'BigIntTransfomer' => ColumnShapeKind.bigInt,
    'BlobTransformer' => ColumnShapeKind.blob,
    'BooleanTransformer' => ColumnShapeKind.boolean,
    'DateTimeTransfomer' => ColumnShapeKind.dateTime,
    'MapTransformer' => ColumnShapeKind.map,
    'ListTransformer' => ColumnShapeKind.list,
    'PhotoTransformer' => ColumnShapeKind.photo,
    'PhotosTransformer' => ColumnShapeKind.photos,
    _ => _kindFromSqlType(column.sqlType),
  };
}

ColumnShapeKind _kindFromSqlType(String? sqlType) {
  return switch (sqlType?.toUpperCase()) {
    'INTEGER' => ColumnShapeKind.integer,
    'REAL' => ColumnShapeKind.real,
    'BLOB' => ColumnShapeKind.blob,
    'TEXT' => ColumnShapeKind.text,
    _ => ColumnShapeKind.text,
  };
}
