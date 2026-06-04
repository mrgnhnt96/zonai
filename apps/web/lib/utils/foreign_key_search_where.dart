import 'package:zonai_schema/payloads.dart';

/// Builds a server [Where] for FK picker text search, or null when [query] is empty.
Where? buildForeignKeySearchWhere({
  required String query,
  required TableSchemaShape? schema,
  required String referencedColumnName,
  List<String> columnNamesFallback = const [],
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;

  final columns = searchableForeignKeyColumnNames(
    schema: schema,
    referencedColumnName: referencedColumnName,
    columnNamesFallback: columnNamesFallback,
  );
  if (columns.isEmpty) return null;

  final clauses = [for (final name in columns) Contains(name, trimmed)];
  if (clauses.length == 1) return clauses.first;
  return Or(clauses);
}

/// Column names to include in FK picker search.
List<String> searchableForeignKeyColumnNames({
  required TableSchemaShape? schema,
  required String referencedColumnName,
  List<String> columnNamesFallback = const [],
}) {
  if (schema != null && schema.columns.isNotEmpty) {
    final names = <String>[];
    for (final shape in schema.columns) {
      if (shape.isSecret) continue;
      if (!_isSearchableKind(shape.kind)) continue;
      if (!names.contains(shape.name)) names.add(shape.name);
    }
    if (names.isNotEmpty) return names;
  }

  final fallback = <String>{referencedColumnName, ...columnNamesFallback};
  return fallback.toList();
}

bool _isSearchableKind(ColumnShapeKind kind) {
  return switch (kind) {
    ColumnShapeKind.text ||
    ColumnShapeKind.email ||
    ColumnShapeKind.enum_ ||
    ColumnShapeKind.id ||
    ColumnShapeKind.integer ||
    ColumnShapeKind.bigInt => true,
    _ => false,
  };
}

/// [Where] used to verify a manually entered FK value exists.
Where eqForeignKeyReferenceWhere({
  required ForeignKeyShape foreignKey,
  required Object parsedValue,
}) {
  return Eq(foreignKey.column, parsedValue);
}
