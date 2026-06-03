import 'package:zonai_schema/payloads.dart';

/// Stable identity for a table row (primary key columns, or all columns if none).
String tableRowKey(List<Object?> row, List<ColumnShape> columnShapes) {
  final pkIndices = <int>[
    for (var i = 0; i < columnShapes.length; i++)
      if (columnShapes[i].isPrimaryKey) i,
  ];

  if (pkIndices.isEmpty) {
    return row.map((v) => v?.toString() ?? '').join('\x1e');
  }

  return [
    for (final i in pkIndices) '${columnShapes[i].name}=${row[i]}',
  ].join('|');
}

/// [Where] clause that matches a single row, or null if the row cannot be targeted.
Where? tableRowWhere({
  required List<Object?> row,
  required List<String> columns,
  required List<ColumnShape> columnShapes,
}) {
  final pkShapes = columnShapes.where((s) => s.isPrimaryKey).toList();
  if (pkShapes.isEmpty) return null;

  final conditions = <Where>[];
  for (final shape in pkShapes) {
    final index = columns.indexOf(shape.name);
    if (index < 0) return null;
    final value = row[index];
    if (value == null) return null;
    conditions.add(Eq(shape.name, value));
  }

  return switch (conditions.length) {
    0 => null,
    1 => conditions.single,
    _ => And(conditions),
  };
}
