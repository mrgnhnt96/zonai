import 'dart:convert';
import 'dart:typed_data';

import 'table_cell_edit.dart';

/// JSON-safe representation of a cell value for export and display.
Object? jsonEncodableCellValue(Object? value) {
  return switch (value) {
    DateTime d => d.millisecondsSinceEpoch,
    Uint8List bytes => base64Encode(bytes),
    final Map m => {
      for (final entry in m.entries)
        entry.key.toString(): jsonEncodableCellValue(entry.value),
    },
    final List l => [for (final e in l) jsonEncodableCellValue(e)],
    _ => value,
  };
}

Map<String, Object?> tableRowToJsonMap({
  required List<String> columns,
  required List<Object?> row,
}) {
  return {
    for (var i = 0; i < columns.length; i++)
      columns[i]: jsonEncodableCellValue(i < row.length ? row[i] : null),
  };
}

String encodeTableRowsAsJson({
  required List<String> columns,
  required List<List<Object?>> rows,
}) {
  final maps = [
    for (final row in rows) tableRowToJsonMap(columns: columns, row: row),
  ];
  try {
    return formatDisplayJson(maps);
  } on Object {
    return formatDisplayJson([
      for (final map in maps)
        {for (final entry in map.entries) entry.key: entry.value?.toString()},
    ]);
  }
}
