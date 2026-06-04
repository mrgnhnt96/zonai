import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:zonai_schema/payloads.dart';

const _deepCollectionEquality = DeepCollectionEquality();

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
    ColumnShapeKind.photos => false,
    _ => true,
  };
}

/// Columns whose edit state lives in the row draft list (not [_textInputs]).
bool usesDraftValueColumn(ColumnShape shape) {
  return switch (shape.kind) {
    ColumnShapeKind.boolean ||
    ColumnShapeKind.isVerified ||
    ColumnShapeKind.list ||
    ColumnShapeKind.enumList => true,
    _ => false,
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
    ColumnShapeKind.dateTime || ColumnShapeKind.createdAt || ColumnShapeKind.updatedAt => _formatDateTimeForEdit(value),
    ColumnShapeKind.enum_ => _formatEnumForEdit(value, shape!.enumValues),
    ColumnShapeKind.list => jsonEncode(cellValueAsStringList(value)),
    ColumnShapeKind.enumList => joinCommaSeparatedList(cellValueAsStringList(value, shape!.enumValues)),
    ColumnShapeKind.bigInt => formatBigIntCellString(value),
    ColumnShapeKind.map => _formatMapForEdit(value),
    ColumnShapeKind.blob =>
      effectiveColumnEditKind(shape!, value) == ColumnShapeKind.bigInt
          ? formatBigIntCellString(value)
          : _formatBlobForEdit(value),
    _ => '$value',
  };
}

/// Wire text for picker-backed columns (UTC ms for datetimes).
String cellToEditWireText(Object? value, ColumnShape? shape) {
  if (value == null) return '';
  if (shape != null && isDateTimeColumnKind(shape.kind)) {
    final dt = _toDateTime(value);
    if (dt != null) return '${dt.toUtc().millisecondsSinceEpoch}';
  }
  return cellToEditString(value, shape);
}

/// Normalizes API values into edit-friendly Dart values for [_draft].
Object? normalizeCellValueForEdit(Object? value, ColumnShape shape) {
  if (value == null) return null;

  return switch (shape.kind) {
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => cellEditValueAsBool(value),
    ColumnShapeKind.list => cellValueAsStringList(value),
    ColumnShapeKind.enumList => cellValueAsStringList(value, shape.enumValues),
    ColumnShapeKind.dateTime => _toDateTime(value),
    ColumnShapeKind.enum_ => _formatEnumForEdit(value, shape.enumValues),
    ColumnShapeKind.bigInt => tryParseBigIntCell(value) ?? value,
    ColumnShapeKind.map => _normalizeMapForEdit(value),
    ColumnShapeKind.blob =>
      effectiveColumnEditKind(shape, value) == ColumnShapeKind.bigInt
          ? (tryParseBigIntCell(value) ?? value)
          : _normalizeBlobForEdit(value),
    _ => value,
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
Object? parseEditValue({required Object? draftValue, required String textInput, required ColumnShape shape}) {
  if (usesDraftValueColumn(shape)) {
    return parseDraftCellValue(draftValue: draftValue, shape: shape);
  }

  final trimmed = textInput.trim();
  if (trimmed.isEmpty) {
    if (shape.isNullable) return null;
    throw FormatException('${shape.name} is required');
  }

  final editKind = effectiveColumnEditKind(shape, draftValue);

  return switch (editKind) {
    ColumnShapeKind.integer => int.parse(trimmed),
    ColumnShapeKind.id => trimmed,
    ColumnShapeKind.real => double.parse(trimmed),
    ColumnShapeKind.bigInt => _parseBigIntEditValue(trimmed, shape: shape),
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => _parseBool(trimmed),
    ColumnShapeKind.enum_ => _parseEnum(trimmed, shape.enumValues),
    ColumnShapeKind.dateTime => _parseDateTime(trimmed),
    ColumnShapeKind.map => parseMapEditValue(trimmed),
    ColumnShapeKind.blob => _parseBlobEditValue(trimmed),
    _ => trimmed,
  };
}

/// Parses a draft cell value (from typed editors). Throws [FormatException] on invalid input.
Object? parseDraftCellValue({required Object? draftValue, required ColumnShape shape}) {
  if (draftValue == null) {
    if (shape.isNullable) return null;
    throw FormatException('${shape.name} is required');
  }

  return switch (shape.kind) {
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => cellEditValueAsBool(draftValue),
    ColumnShapeKind.list => parseListEditValue(draftValue),
    ColumnShapeKind.enumList => parseEnumListEditValue(draftValue, shape.enumValues),
    _ => draftValue,
  };
}

List<String> cellValueAsStringList(Object? value, [List<String> enumValues = const []]) {
  if (value == null) return const [];

  if (value is List) {
    return [
      for (final item in value)
        if (item != null) _formatEnumForEdit(item, enumValues),
    ];
  }

  if (value is String) {
    if (value.isEmpty) return const [];
    if (value.startsWith('[')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return [
            for (final item in decoded)
              if (item != null) _formatEnumForEdit(item, enumValues),
          ];
        }
      } on FormatException {
        // fall through to comma split
      }
    }
    return parseCommaSeparatedList(value);
  }

  return ['$value'];
}

List<String> parseListEditValue(Object? draftValue) {
  final items = cellValueAsStringList(draftValue);
  if (items.isEmpty && draftValue != null && '$draftValue'.trim().isNotEmpty) {
    throw FormatException('Invalid list value');
  }
  return items;
}

String parseEnumListEditValue(Object? draftValue, List<String> enumValues) {
  final items = parseListEditValue(draftValue);
  for (final item in items) {
    if (!enumValues.contains(item)) {
      throw FormatException('Invalid value; expected one of: ${enumValues.join(', ')}');
    }
  }
  return joinCommaSeparatedList(items);
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

  if (shape?.kind == ColumnShapeKind.boolean || shape?.kind == ColumnShapeKind.isVerified) {
    return cellEditValueAsBool(a) == cellEditValueAsBool(b);
  }

  if (shape?.kind == ColumnShapeKind.enum_) {
    final enumValues = shape?.enumValues ?? const [];
    return _formatEnumForEdit(a, enumValues) == _formatEnumForEdit(b, enumValues);
  }

  if (shape?.kind == ColumnShapeKind.id) {
    final sa = a.toString();
    final sb = b.toString();
    return sa == sb;
  }

  if (shape?.kind == ColumnShapeKind.dateTime ||
      shape?.kind == ColumnShapeKind.createdAt ||
      shape?.kind == ColumnShapeKind.updatedAt) {
    return _dateTimesEqualForEdit(a, b);
  }

  if (shape?.kind == ColumnShapeKind.integer) {
    final ia = _toInt(a);
    final ib = _toInt(b);
    if (ia != null && ib != null) return ia == ib;
  }

  if (shape?.kind == ColumnShapeKind.real) {
    final na = _toDouble(a);
    final nb = _toDouble(b);
    if (na != null && nb != null) return na == nb;
  }

  if (shape?.kind == ColumnShapeKind.list || shape?.kind == ColumnShapeKind.enumList) {
    final la = cellValueAsStringList(a, shape?.enumValues ?? const []);
    final lb = cellValueAsStringList(b, shape?.enumValues ?? const []);
    return _deepCollectionEquality.equals(la, lb);
  }

  if (shape?.kind == ColumnShapeKind.bigInt) {
    final ba = _toBigInt(a);
    final bb = _toBigInt(b);
    if (ba != null && bb != null) return ba == bb;
  }

  if (shape?.kind == ColumnShapeKind.map) {
    final ma = _normalizeMapForEdit(a);
    final mb = _normalizeMapForEdit(b);
    if (ma is Map && mb is Map) {
      return _deepCollectionEquality.equals(ma, mb);
    }
  }

  if (shape?.kind == ColumnShapeKind.blob) {
    if (isBigIntWireValue(a) || isBigIntWireValue(b)) {
      final ba = tryParseBigIntCell(a);
      final bb = tryParseBigIntCell(b);
      if (ba != null && bb != null) return ba == bb;
    }
    final ba = _blobBytesForEquality(a);
    final bb = _blobBytesForEquality(b);
    if (ba != null && bb != null) return _listEquality.equals(ba, bb);
  }

  return '$a' == '$b';
}

const _listEquality = ListEquality<int>();

Object? _decodeJsonEditValue(Object value) {
  if (value is Map || value is List) return value;
  if (value is! String || value.isEmpty) return null;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

/// Pretty-printed JSON for map/blob editors and row detail; BigInt byte arrays stay on one line.
String formatDisplayJson(Object? value) {
  final buffer = StringBuffer();
  _writeDisplayJson(value, buffer, depth: 0);
  return buffer.toString();
}

const _displayJsonIndent = '  ';

void _writeDisplayJson(Object? value, StringBuffer out, {required int depth}) {
  final pad = _displayJsonIndent * depth;
  final padInner = _displayJsonIndent * (depth + 1);

  if (value == null) {
    out.write('null');
    return;
  }
  if (value is num || value is bool || value is String) {
    out.write(jsonEncode(value));
    return;
  }
  if (value is Uint8List) {
    _writeDisplayJson(value.toList(), out, depth: depth);
    return;
  }
  if (value is List) {
    if (_isIntByteList(value)) {
      out.write(jsonEncode(_intListWire(value)));
      return;
    }
    if (value.isEmpty) {
      out.write('[]');
      return;
    }
    out.writeln('[');
    for (var i = 0; i < value.length; i++) {
      out.write(padInner);
      _writeDisplayJson(value[i], out, depth: depth + 1);
      if (i < value.length - 1) out.write(',');
      out.writeln();
    }
    out.write('$pad]');
    return;
  }
  if (value is Map) {
    if (value.isEmpty) {
      out.write('{}');
      return;
    }
    out.writeln('{');
    final entries = value.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      out.write(padInner);
      out.write(jsonEncode(entry.key.toString()));
      out.write(': ');
      _writeDisplayJson(entry.value, out, depth: depth + 1);
      if (i < entries.length - 1) out.write(',');
      out.writeln();
    }
    out.write('$pad}');
    return;
  }
  out.write(jsonEncode('$value'));
}

List<int> _intListWire(List list) {
  return [for (final item in list) if (item is int) item else int.parse('$item')];
}

/// Byte arrays and BigInt binary-digit wire: keep `[…]` on one line (e.g. after `"payload":`).
bool _isIntByteList(List list) {
  if (list.isEmpty) return true;
  for (final item in list) {
    if (item is! int) return false;
  }
  return true;
}

String _formatStructuredJson(Object value) {
  final decoded = _decodeJsonEditValue(value) ?? value;
  try {
    return formatDisplayJson(decoded);
  } on Object {
    return '$decoded';
  }
}

/// True when [value] is BigInt binary-digit wire (each byte is 0 or 1), not arbitrary blob bytes.
bool isBigIntWireValue(Object? value) => isBinaryDigitBlobWire(value);

/// Binary-digit blob wire (BigInt transformer), including short bit sequences.
bool isBinaryDigitBlobWire(Object? value) {
  final bytes = _blobBytesForEquality(value);
  if (bytes == null || bytes.isEmpty) return false;
  if (!bytes.every((b) => b == 0 || b == 1)) return false;
  return tryParseBigIntCell(value) != null;
}

/// BLOB columns declared as BigInt in schema (e.g. `big_count`) when wire is not yet loaded.
bool isLikelyBigIntBlobColumn(ColumnShape shape) {
  if (shape.kind != ColumnShapeKind.blob) return false;
  final name = shape.name.toLowerCase();
  return name.contains('bigint') || name.contains('big_int') || name == 'big_count';
}

bool _isScalarBigIntValue(Object value) {
  return switch (value) {
    BigInt _ => true,
    int _ => true,
    String s => BigInt.tryParse(s) != null,
    _ => false,
  };
}

/// UI routing kind; treats misclassified blob columns with BigInt wire as [ColumnShapeKind.bigInt].
ColumnShapeKind effectiveColumnEditKind(ColumnShape shape, [Object? value]) {
  if (shape.kind == ColumnShapeKind.bigInt) return ColumnShapeKind.bigInt;
  if (shape.kind == ColumnShapeKind.blob) {
    if (isLikelyBigIntBlobColumn(shape)) return ColumnShapeKind.bigInt;
    if (value != null) {
      if (isBinaryDigitBlobWire(value) || _isScalarBigIntValue(value)) {
        return ColumnShapeKind.bigInt;
      }
    }
  }
  return shape.kind;
}

/// Keeps only an optional leading minus and decimal digits (for BigInt text inputs).
String filterBigIntDecimalInput(String text) {
  if (text.isEmpty) return text;
  final negative = text.startsWith('-');
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return negative ? '-' : '';
  return negative ? '-$digits' : digits;
}

/// Decimal string for [ColumnShapeKind.bigInt] wire values (including binary-digit blobs).
String formatBigIntCellString(Object? value) {
  if (value == null) return '';
  final parsed = tryParseBigIntCell(value);
  if (parsed != null) return parsed.toString();
  return '$value';
}

String _formatMapForEdit(Object value) => _formatStructuredJson(value);

String _formatBlobForEdit(Object value) {
  final bytes = _blobBytesForEquality(value);
  if (bytes != null) {
    return formatDisplayJson(bytes);
  }
  return _formatStructuredJson(value);
}

Object? _normalizeMapForEdit(Object value) {
  final decoded = _decodeJsonEditValue(value);
  if (decoded is Map) {
    return Map<String, dynamic>.from(
      decoded.map((key, v) => MapEntry(key.toString(), v)),
    );
  }
  return value;
}

Uint8List? _normalizeBlobForEdit(Object value) {
  final bytes = _blobBytesForEquality(value);
  if (bytes != null) return Uint8List.fromList(bytes);
  return value is Uint8List ? value : null;
}

List<int>? _blobBytesForEquality(Object? value) {
  if (value == null) return null;

  if (value is Uint8List) return value;
  if (value is List<int>) return value;

  if (value is List) {
    final bytes = <int>[];
    for (final item in value) {
      if (item is! int) return null;
      bytes.add(item);
    }
    return bytes;
  }

  if (value is String && value.startsWith('[')) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      final bytes = <int>[];
      for (final item in decoded) {
        if (item is! int) return null;
        bytes.add(item);
      }
      return bytes;
    } on FormatException {
      return null;
    }
  }

  return null;
}

/// Returns a user-facing error, or null when [text] is valid map column JSON.
String? validateMapEditText(String text, {required bool allowEmpty}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return allowEmpty ? null : 'Enter a JSON object';
  try {
    parseMapEditValue(trimmed);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// Parses map column text into [Map<String, dynamic>]. Throws [FormatException] when invalid.
Map<String, dynamic> parseMapEditValue(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Enter a JSON object');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException catch (e) {
    throw FormatException(_friendlyJsonSyntaxMessage(e.message));
  }

  if (decoded is! Map) {
    throw FormatException(_mapTopLevelTypeMessage(decoded));
  }

  return Map<String, dynamic>.from(
    decoded.map((key, value) => MapEntry(key.toString(), value)),
  );
}

String _friendlyJsonSyntaxMessage(String detail) {
  final lower = detail.toLowerCase();
  if (lower.contains('unexpected character') || lower.contains('unexpected end')) {
    return 'Invalid JSON; check braces, quotes, and commas';
  }
  return 'Invalid JSON; expected an object like {"key": "value"}';
}

String _mapTopLevelTypeMessage(Object? decoded) {
  return switch (decoded) {
    List _ => 'Expected a JSON object with keys, not an array',
    String _ => 'Expected a JSON object with keys, not a string',
    num _ => 'Expected a JSON object with keys, not a number',
    bool _ => 'Expected a JSON object with keys, not true or false',
    null => 'Expected a JSON object with keys, not null',
    _ => 'Expected a JSON object with keys',
  };
}

Object? _parseBigIntEditValue(String text, {required ColumnShape shape}) {
  if (!RegExp(r'^-?\d+$').hasMatch(text)) {
    throw const FormatException('Expected a whole number');
  }
  final parsed = BigInt.parse(text);
  if (shape.kind == ColumnShapeKind.blob) {
    return encodeBigIntWire(parsed);
  }
  return parsed;
}

/// Binary-digit blob wire format used by [BigIntTransfomer].
Uint8List encodeBigIntWire(BigInt value) => Uint8List.fromList(
  value.toRadixString(2).split('').map(int.parse).toList(),
);

Uint8List _parseBlobEditValue(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Invalid blob value');
  }

  final decoded = jsonDecode(trimmed);
  if (decoded is! List) {
    throw const FormatException('Invalid JSON array; expected byte list like [0,1,1]');
  }
  final bytes = <int>[];
  for (final item in decoded) {
    if (item is! int) {
      throw const FormatException('Invalid blob byte; expected integers');
    }
    bytes.add(item);
  }
  return Uint8List.fromList(bytes);
}

BigInt? _toBigInt(Object value) => tryParseBigIntCell(value);

DateTime? _toDateTime(Object value) => switch (value) {
  DateTime d => d,
  int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  num n => DateTime.fromMillisecondsSinceEpoch(n.toInt(), isUtc: true),
  String s => DateTime.tryParse(s),
  _ => null,
};

/// Edit panel datetimes are picked to minute precision (no seconds in wire round-trip).
bool _dateTimesEqualForEdit(Object? a, Object? b) {
  if (a == null || b == null) return a == b;

  final da = _toDateTime(a);
  final db = _toDateTime(b);
  if (da == null || db == null) return false;

  final au = da.toUtc();
  final bu = db.toUtc();
  return au.year == bu.year &&
      au.month == bu.month &&
      au.day == bu.day &&
      au.hour == bu.hour &&
      au.minute == bu.minute;
}

double? _toDouble(Object value) => switch (value) {
  double d => d,
  num n => n.toDouble(),
  String s => double.tryParse(s),
  _ => null,
};

int? _toInt(Object value) => switch (value) {
  int i => i,
  num n when n == n.roundToDouble() => n.toInt(),
  String s => int.tryParse(s),
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

bool isForeignKeyColumn(ColumnShape shape) => shape.foreignKey != null;

bool isDateTimeColumnKind(ColumnShapeKind kind) =>
    kind == ColumnShapeKind.dateTime ||
    kind == ColumnShapeKind.createdAt ||
    kind == ColumnShapeKind.updatedAt;

/// HTML input attributes for native typed inputs (filter + edit).
Map<String, String> validationAttributesForShape(ColumnShape shape) {
  return switch (shape.kind) {
    ColumnShapeKind.integer || ColumnShapeKind.bigInt => const {
      'inputmode': 'numeric',
      'step': '1',
    },
    ColumnShapeKind.real => const {'inputmode': 'decimal', 'step': 'any'},
    ColumnShapeKind.email => const {'inputmode': 'email', 'type': 'email'},
    _ => const {},
  };
}

/// `datetime-local` value from filter/edit text or empty.
String dateTimeTextToLocalInputValue(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';

  try {
    final dt = _parseDateTime(trimmed);
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-${d}T$h:$min';
  } catch (_) {
    return '';
  }
}

/// Stores UTC ms in wire format used by filters (numeric string).
String localDateTimeInputToFilterText(String localValue) {
  final trimmed = localValue.trim();
  if (trimmed.isEmpty) return '';
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return trimmed;
  final utc = parsed.isUtc ? parsed : parsed.toUtc();
  return '${utc.millisecondsSinceEpoch}';
}

/// Filter/edit datetime as local wall time, or null when empty or invalid.
DateTime? filterDateTimeTextToLocal(String text) => filterDateTimeTextToWall(text, useUtc: false);

/// Filter datetime as wall time in [useUtc] zone (local or UTC), or null when empty.
DateTime? filterDateTimeTextToWall(String text, {required bool useUtc}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  try {
    final instant = _parseDateTime(trimmed);
    return useUtc ? instant : instant.toLocal();
  } catch (_) {
    return null;
  }
}

/// UTC ms wire format from wall [DateTime] (local or UTC per [useUtc]).
String wallDateTimeToFilterText(DateTime wall, {required bool useUtc}) {
  if (useUtc) {
    final utc = wall.isUtc
        ? wall
        : DateTime.utc(
            wall.year,
            wall.month,
            wall.day,
            wall.hour,
            wall.minute,
            wall.second,
            wall.millisecond,
          );
    return '${utc.millisecondsSinceEpoch}';
  }
  final local = wall.isUtc ? wall.toLocal() : wall;
  return localWallDateTimeToFilterText(local);
}

/// UTC ms wire format from a local [DateTime] (date + time in local zone).
String localWallDateTimeToFilterText(DateTime local) {
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return localDateTimeInputToFilterText('$y-$m-${d}T$h:$min');
}

const _monthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// 12-hour clock (1–12) and AM/PM from 24-hour [hour] (0–23).
(int hour12, bool isPm) hour24To12Parts(int hour) {
  final isPm = hour >= 12;
  final h = hour % 12;
  return (h == 0 ? 12 : h, isPm);
}

/// 24-hour clock (0–23) from 12-hour [hour12] (1–12) and [isPm].
int hour12To24(int hour12, bool isPm) {
  final clamped = hour12.clamp(1, 12);
  if (isPm) return clamped == 12 ? 12 : clamped + 12;
  return clamped == 12 ? 0 : clamped;
}

/// Local time as `h:mm AM/PM` (12-hour).
String formatTime12(DateTime local) {
  final (hour12, isPm) = hour24To12Parts(local.hour);
  final min = local.minute.toString().padLeft(2, '0');
  return '$hour12:$min ${isPm ? 'PM' : 'AM'}';
}

/// Display label for datetime picker triggers (wall time in local or UTC).
String formatFilterDateTimeDisplay(DateTime wall, {bool useUtc = false}) {
  final month = _monthAbbrev[wall.month - 1];
  final day = wall.day;
  final year = wall.year;
  final suffix = useUtc ? ' UTC' : '';
  return '$day $month $year, ${formatTime12(wall)}$suffix';
}

/// Days in [month] (1–12) for [year], for calendar grids.
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Sunday-start column (0–6) for the first day of [month] (1–12).
int firstWeekdaySundayStart(int year, int month) => DateTime(year, month, 1).weekday % 7;

List<String> parseCommaSeparatedList(String text) =>
    text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

String joinCommaSeparatedList(List<String> values) => values.join(',');
