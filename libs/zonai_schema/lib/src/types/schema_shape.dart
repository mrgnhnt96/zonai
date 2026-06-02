import 'package:zonai_schema/src/types/column_shape_kind.dart';

/// Foreign-key target for a column.
final class ForeignKeyShape {
  const ForeignKeyShape({
    required this.table,
    required this.column,
  });

  final String table;
  final String column;

  factory ForeignKeyShape.fromJson(Map<String, dynamic> json) {
    return ForeignKeyShape(
      table: json['table'] as String,
      column: json['column'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'table': table,
    'column': column,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForeignKeyShape &&
          table == other.table &&
          column == other.column;

  @override
  int get hashCode => Object.hash(table, column);
}

/// Describes one column for UI rendering and validation hints.
final class ColumnShape {
  const ColumnShape({
    required this.name,
    required this.kind,
    required this.isNullable,
    required this.isPrimaryKey,
    required this.autoIncrement,
    required this.sqlType,
    this.defaultValue,
    this.foreignKey,
    this.enumValues = const [],
    this.isSecret = false,
    this.isReadOnly = false,
  });

  final String name;
  final ColumnShapeKind kind;
  final bool isNullable;
  final bool isPrimaryKey;
  final bool autoIncrement;
  final String sqlType;
  final String? defaultValue;
  final ForeignKeyShape? foreignKey;
  final List<String> enumValues;
  final bool isSecret;
  final bool isReadOnly;

  factory ColumnShape.fromJson(Map<String, dynamic> json) {
    return ColumnShape(
      name: json['name'] as String,
      kind: ColumnShapeKind.fromJson(json['kind'] as String),
      isNullable: json['isNullable'] as bool,
      isPrimaryKey: json['isPrimaryKey'] as bool? ?? false,
      autoIncrement: json['autoIncrement'] as bool? ?? false,
      sqlType: json['sqlType'] as String,
      defaultValue: json['defaultValue'] as String?,
      foreignKey: json['foreignKey'] != null
          ? ForeignKeyShape.fromJson(
              Map<String, dynamic>.from(json['foreignKey'] as Map),
            )
          : null,
      enumValues: [
        if (json['enumValues'] case final List list)
          for (final value in list) value as String,
      ],
      isSecret: json['isSecret'] as bool? ?? false,
      isReadOnly: json['isReadOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.toJson(),
    'isNullable': isNullable,
    'isPrimaryKey': isPrimaryKey,
    'autoIncrement': autoIncrement,
    'sqlType': sqlType,
    if (defaultValue != null) 'defaultValue': defaultValue,
    if (foreignKey != null) 'foreignKey': foreignKey!.toJson(),
    if (enumValues.isNotEmpty) 'enumValues': enumValues,
    if (isSecret) 'isSecret': isSecret,
    if (isReadOnly) 'isReadOnly': isReadOnly,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ColumnShape &&
        name == other.name &&
        kind == other.kind &&
        isNullable == other.isNullable &&
        isPrimaryKey == other.isPrimaryKey &&
        autoIncrement == other.autoIncrement &&
        sqlType == other.sqlType &&
        defaultValue == other.defaultValue &&
        foreignKey == other.foreignKey &&
        _listEquals(enumValues, other.enumValues) &&
        isSecret == other.isSecret &&
        isReadOnly == other.isReadOnly;
  }

  @override
  int get hashCode => Object.hash(
    name,
    kind,
    isNullable,
    isPrimaryKey,
    autoIncrement,
    sqlType,
    defaultValue,
    foreignKey,
    Object.hashAll(enumValues),
    isSecret,
    isReadOnly,
  );
}

/// Full schema metadata for a collection table.
final class TableSchemaShape {
  const TableSchemaShape({
    required this.table,
    required this.columns,
  });

  final String table;
  final List<ColumnShape> columns;

  factory TableSchemaShape.fromJson(Map<String, dynamic> json) {
    return TableSchemaShape(
      table: json['table'] as String,
      columns: [
        for (final item in json['columns'] as List)
          ColumnShape.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'table': table,
    'columns': [for (final column in columns) column.toJson()],
  };

  ColumnShape? columnNamed(String name) {
    for (final column in columns) {
      if (column.name == name) return column;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableSchemaShape &&
        table == other.table &&
        _listEquals(columns, other.columns);
  }

  @override
  int get hashCode => Object.hash(table, Object.hashAll(columns));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
