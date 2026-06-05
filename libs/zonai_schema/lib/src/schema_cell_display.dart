import 'dart:convert';
import 'dart:typed_data';

import 'package:zonai_schema/src/types/column_shape_kind.dart';
import 'package:zonai_schema/src/types/schema_shape.dart';

/// Parses a [ColumnShapeKind.bigInt] value from `/db/list` wire forms.
BigInt? tryParseBigIntCell(Object? value) {
  if (value == null) return null;

  return switch (value) {
    BigInt b => b,
    Uint8List bytes => _bigIntFromBinaryDigitBlob(bytes),
    List bytes when bytes.isNotEmpty && bytes.every(_isBinaryDigit) => _bigIntFromBinaryDigitBlob(bytes),
    int i => BigInt.from(i),
    num n => BigInt.from(n.toInt()),
    String s => BigInt.tryParse(s),
    _ => null,
  };
}

/// Human-readable table header for a [ColumnShape].
String columnShapeHeaderLabel(ColumnShape shape) => shape.name;

/// Formats a raw cell value from `/db/list` using [shape] metadata.
///
/// When [truncate] is false (e.g. row detail panel), photo URLs and blob text
/// are not shortened.
String formatSchemaCell(
  Object? value,
  ColumnShape? shape, {
  bool truncate = true,
  bool revealSecrets = false,
}) {
  if (value == null) return '—';
  if (!revealSecrets && (shape?.isSecret == true || shape?.kind == ColumnShapeKind.password)) {
    return '••••••••';
  }

  return switch (shape?.kind) {
    ColumnShapeKind.boolean ||
    ColumnShapeKind.isVerified => _formatBoolean(value),
    ColumnShapeKind.integer || ColumnShapeKind.id => _formatInteger(value),
    ColumnShapeKind.real => _formatReal(value),
    ColumnShapeKind.bigInt => _formatBigInt(value),
    ColumnShapeKind.dateTime ||
    ColumnShapeKind.createdAt ||
    ColumnShapeKind.updatedAt => _formatDateTime(value),
    ColumnShapeKind.enum_ => _formatEnum(value, shape!.enumValues),
    ColumnShapeKind.enumList => _formatEnumList(value, shape!.enumValues),
    ColumnShapeKind.photo => _formatPhoto(value, truncate: truncate),
    ColumnShapeKind.photos => _formatPhotos(value, truncate: truncate),
    ColumnShapeKind.map || ColumnShapeKind.list => _formatStructured(value),
    ColumnShapeKind.blob => _formatBlob(value, truncate: truncate),
    _ => '$value',
  };
}

String _formatBoolean(Object value) => switch (value) {
  true || 1 || '1' || 'true' => 'Yes',
  false || 0 || '0' || 'false' => 'No',
  _ => '$value',
};

String _formatInteger(Object value) {
  return switch (value) {
    int i => i.toString(),
    num n => n.toInt().toString(),
    String s => int.tryParse(s)?.toString() ?? s,
    _ => '$value',
  };
}

String _formatReal(Object value) {
  return switch (value) {
    double d => d.toString(),
    num n => n.toString(),
    String s => double.tryParse(s)?.toString() ?? s,
    _ => '$value',
  };
}

String _formatBigInt(Object value) => tryParseBigIntCell(value)?.toString() ?? '$value';

bool _isBinaryDigit(Object? digit) => digit == 0 || digit == 1 || digit == '0' || digit == '1';

BigInt _bigIntFromBinaryDigitBlob(Iterable<Object?> bytes) =>
    BigInt.parse(bytes.map((b) => b.toString()).join(), radix: 2);

String _formatDateTime(Object value) {
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

String _formatEnum(Object value, List<String> enumValues) {
  if (value is String) return value;
  if (value is int && enumValues.isNotEmpty) {
    final index = value;
    if (index >= 0 && index < enumValues.length) return enumValues[index];
  }
  return '$value';
}

String _formatEnumList(Object value, List<String> enumValues) {
  final list = _asList(value);
  if (list == null) return _formatStructured(value);

  final labels = [
    for (final item in list)
      if (item != null) _formatEnum(item, enumValues),
  ];
  return labels.join(', ');
}

String _formatPhoto(Object value, {required bool truncate}) {
  final text = '$value';
  if (text.startsWith('http://') || text.startsWith('https://')) {
    return truncate ? _truncate(text, 64) : text;
  }
  return text;
}

String _formatPhotos(Object value, {required bool truncate}) {
  final list = _asList(value);
  if (list == null) return _formatStructured(value);
  if (list.isEmpty) return '—';

  final urls = [
    for (final item in list)
      if (item != null) _formatPhoto(item, truncate: truncate),
  ];
  if (urls.length == 1) return urls.single;
  if (!truncate) return urls.join('\n');
  return '${urls.length} photos';
}

String _formatStructured(Object value) {
  final decoded = _decodeJsonValue(value);
  if (decoded == null) return '$value';

  const encoder = JsonEncoder.withIndent('  ');
  try {
    return encoder.convert(decoded);
  } on Object {
    return '$decoded';
  }
}

String _formatBlob(Object value, {required bool truncate}) {
  // BigInt columns are stored as BLOB; misclassified shapes still arrive as 0/1 digit lists.
  if (value is List && value.isNotEmpty && value.every(_isBinaryDigit)) {
    return _formatBigInt(value);
  }

  return switch (value) {
    final List<int> bytes => 'BLOB (${bytes.length} bytes)',
    final String s when s.isEmpty => '—',
    final String s => truncate ? _truncate(s, 80) : s,
    _ => '$value',
  };
}

Object? _decodeJsonValue(Object value) {
  if (value is Map || value is List) return value;
  if (value is! String || value.isEmpty) return null;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

List<Object?>? _asList(Object value) {
  if (value is List) return value;
  final decoded = _decodeJsonValue(value);
  if (decoded is List) return decoded;
  return null;
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength - 1)}…';
}
