import 'dart:convert';
import 'dart:typed_data';

import 'table_cell_edit.dart';

/// Column map safe for DB create/update HTTP bodies ([CreateBody], [ObjectUpdate]).
Map<String, dynamic> apiWireObject(Map<String, Object?> fields) {
  final encoded = jsonEncode({
    for (final entry in fields.entries) entry.key: mutationValueToJsonEncodable(entry.value),
  });
  return (jsonDecode(encoded) as Map).cast<String, dynamic>();
}

/// JSON-safe cell values for create/update payloads (stricter than [jsonEncodableCellValue]).
Object? mutationValueToJsonEncodable(Object? value) {
  return switch (value) {
    BigInt b => b.toString(),
    DateTime d => d.millisecondsSinceEpoch,
    Uint8List bytes => base64Encode(bytes),
    final Map m => {for (final entry in m.entries) entry.key.toString(): mutationValueToJsonEncodable(entry.value)},
    final List l => [for (final e in l) mutationValueToJsonEncodable(e)],
    _ => value,
  };
}

/// JSON-safe representation of a cell value for export and display.
Object? jsonEncodableCellValue(Object? value) {
  return mutationValueToJsonEncodable(value);
}

Map<String, Object?> tableRowToJsonMap({required List<String> columns, required List<Object?> row}) {
  return {for (var i = 0; i < columns.length; i++) columns[i]: jsonEncodableCellValue(i < row.length ? row[i] : null)};
}

String encodeTableRowsAsJson({required List<String> columns, required List<List<Object?>> rows}) {
  final maps = [for (final row in rows) tableRowToJsonMap(columns: columns, row: row)];
  try {
    return formatDisplayJson(maps);
  } on Object {
    return formatDisplayJson([
      for (final map in maps) {for (final entry in map.entries) entry.key: entry.value?.toString()},
    ]);
  }
}
