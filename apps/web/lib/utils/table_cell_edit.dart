import 'package:zonai_schema/payloads.dart';

/// Whether the admin UI should offer editing for this column.
bool isColumnEditable(ColumnShape shape) {
  if (shape.isPrimaryKey || shape.autoIncrement || shape.isReadOnly || shape.isSecret) {
    return false;
  }

  return switch (shape.kind) {
    ColumnShapeKind.password ||
    ColumnShapeKind.createdAt ||
    ColumnShapeKind.updatedAt ||
    ColumnShapeKind.photo ||
    ColumnShapeKind.photos ||
    ColumnShapeKind.blob ||
    ColumnShapeKind.map ||
    ColumnShapeKind.list ||
    ColumnShapeKind.enumList => false,
    _ => true,
  };
}

bool hasEditableColumns(List<ColumnShape> columnShapes) {
  return columnShapes.any(isColumnEditable);
}

/// String shown in text inputs before editing (not used for checkbox fields).
String cellToEditString(Object? value, ColumnShape? shape) {
  if (value == null) return '';

  return switch (shape?.kind) {
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => '',
    ColumnShapeKind.dateTime ||
    ColumnShapeKind.createdAt ||
    ColumnShapeKind.updatedAt =>
      _formatDateTimeForEdit(value),
    ColumnShapeKind.enum_ => _formatEnumForEdit(value, shape!.enumValues),
    _ => '$value',
  };
}

String _formatDateTimeForEdit(Object value) {
  final DateTime? parsed = switch (value) {
    DateTime d => d,
    int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    num n => DateTime.fromMillisecondsSinceEpoch(n.toInt(), isUtc: true),
    String s => DateTime.tryParse(s),
    _ => null,
  };

  if (parsed == null) return '$value';

  final utc = parsed.isUtc ? parsed : parsed.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  final h = utc.hour.toString().padLeft(2, '0');
  final min = utc.minute.toString().padLeft(2, '0');
  final sec = utc.second.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min:$sec UTC';
}

String _formatEnumForEdit(Object value, List<String> enumValues) {
  if (value is String) return value;
  if (value is int && enumValues.isNotEmpty) {
    final index = value;
    if (index >= 0 && index < enumValues.length) return enumValues[index];
  }
  return '$value';
}

bool cellEditValueAsBool(Object? value) {
  return switch (value) {
    true || 1 || '1' || 'true' => true,
    _ => false,
  };
}

/// Parses user input for a column. Throws [FormatException] on invalid input.
Object? parseEditValue({
  required Object? draftValue,
  required String textInput,
  required ColumnShape shape,
}) {
  if (shape.kind == ColumnShapeKind.boolean || shape.kind == ColumnShapeKind.isVerified) {
    return cellEditValueAsBool(draftValue);
  }

  final trimmed = textInput.trim();
  if (trimmed.isEmpty) {
    if (shape.isNullable) return null;
    throw FormatException('${shape.name} is required');
  }

  return switch (shape.kind) {
    ColumnShapeKind.integer || ColumnShapeKind.id => int.parse(trimmed),
    ColumnShapeKind.real => double.parse(trimmed),
    ColumnShapeKind.bigInt => int.parse(trimmed),
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => _parseBool(trimmed),
    ColumnShapeKind.enum_ => _parseEnum(trimmed, shape.enumValues),
    ColumnShapeKind.dateTime => _parseDateTime(trimmed),
    _ => trimmed,
  };
}

bool _parseBool(String text) {
  return switch (text.toLowerCase()) {
    'yes' || 'true' || '1' => true,
    'no' || 'false' || '0' => false,
    _ => throw FormatException('Expected Yes or No'),
  };
}

String _parseEnum(String text, List<String> enumValues) {
  if (enumValues.contains(text)) return text;
  throw FormatException('Invalid value; expected one of: ${enumValues.join(', ')}');
}

DateTime _parseDateTime(String text) {
  if (RegExp(r'^\d+$').hasMatch(text)) {
    final ms = int.parse(text);
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  final normalized = text.endsWith(' UTC') ? text.replaceFirst(' UTC', 'Z') : text;
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) {
    throw FormatException('Invalid date/time; use YYYY-MM-DD HH:MM:SS UTC or milliseconds');
  }
  return parsed.isUtc ? parsed : parsed.toUtc();
}

/// Whether two cell values are equal for change detection.
bool cellValuesEqual(Object? a, Object? b, ColumnShape? shape) {
  if (a == b) return true;
  if (a == null || b == null) return false;

  if (shape?.kind == ColumnShapeKind.dateTime ||
      shape?.kind == ColumnShapeKind.createdAt ||
      shape?.kind == ColumnShapeKind.updatedAt) {
    final da = _toDateTime(a);
    final db = _toDateTime(b);
    if (da != null && db != null) return da.toUtc() == db.toUtc();
  }

  if (shape?.kind == ColumnShapeKind.real) {
    final na = _toDouble(a);
    final nb = _toDouble(b);
    if (na != null && nb != null) return na == nb;
  }

  return '$a' == '$b';
}

DateTime? _toDateTime(Object value) => switch (value) {
  DateTime d => d,
  int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  num n => DateTime.fromMillisecondsSinceEpoch(n.toInt(), isUtc: true),
  String s => DateTime.tryParse(s),
  _ => null,
};

double? _toDouble(Object value) => switch (value) {
  double d => d,
  num n => n.toDouble(),
  String s => double.tryParse(s),
  _ => null,
};

/// Maps an API record to row column order.
List<Object?> rowFromRecord(Map<String, Object?> record, List<String> columns) {
  return [for (final col in columns) record[col]];
}

/// Builds changed fields only (column name → value).
Map<String, Object?> diffRowUpdates({
  required List<Object?> original,
  required List<Object?> draft,
  required List<String> columns,
  required List<ColumnShape> columnShapes,
}) {
  final updates = <String, Object?>{};
  for (var i = 0; i < columns.length; i++) {
    final shape = columnShapes.elementAtOrNull(i);
    if (shape == null || !isColumnEditable(shape)) continue;
    if (cellValuesEqual(original[i], draft[i], shape)) continue;
    updates[columns[i]] = draft[i];
  }
  return updates;
}

String formatReadOnlyCell(Object? value, ColumnShape? shape) {
  return formatSchemaCell(value, shape, truncate: false);
}
