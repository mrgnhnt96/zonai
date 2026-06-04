import 'dart:convert';

import 'package:zonai_schema/payloads.dart';

/// Returns [rows] sorted by [columnIndex], using [shape] for comparison semantics.
List<List<Object?>> sortTableRows({
  required List<List<Object?>> rows,
  required int columnIndex,
  required ColumnShape? shape,
  required bool ascending,
}) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    final cmp = _compareCellValues(a[columnIndex], b[columnIndex], shape);
    return ascending ? cmp : -cmp;
  });
  return sorted;
}

int _compareCellValues(Object? a, Object? b, ColumnShape? shape) {
  if (identical(a, b)) return 0;
  if (a == null) return 1;
  if (b == null) return -1;

  return switch (shape?.kind) {
    ColumnShapeKind.integer || ColumnShapeKind.id => _compareNum(_asNum(a), _asNum(b)),
    ColumnShapeKind.real => _compareNum(_asNum(a), _asNum(b)),
    ColumnShapeKind.bigInt => _compareBigInt(a, b),
    ColumnShapeKind.boolean || ColumnShapeKind.isVerified => _compareBool(a, b),
    ColumnShapeKind.dateTime ||
    ColumnShapeKind.createdAt ||
    ColumnShapeKind.updatedAt => _compareDateTime(a, b),
    ColumnShapeKind.blob || ColumnShapeKind.map || ColumnShapeKind.list => _compareJson(a, b),
    _ => '$a'.compareTo('$b'),
  };
}

int _compareNum(num? a, num? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

num? _asNum(Object value) => switch (value) {
  num n => n,
  String s => num.tryParse(s),
  _ => null,
};

int _compareBigInt(Object a, Object b) {
  final ai = _asBigInt(a);
  final bi = _asBigInt(b);
  if (ai == null && bi == null) return 0;
  if (ai == null) return 1;
  if (bi == null) return -1;
  return ai.compareTo(bi);
}

BigInt? _asBigInt(Object value) => tryParseBigIntCell(value);

int _compareBool(Object a, Object b) {
  final ai = _asBool(a);
  final bi = _asBool(b);
  if (ai == null && bi == null) return 0;
  if (ai == null) return 1;
  if (bi == null) return -1;
  return ai == bi ? 0 : (ai ? 1 : -1);
}

bool? _asBool(Object value) => switch (value) {
  true || 1 || '1' || 'true' => true,
  false || 0 || '0' || 'false' => false,
  _ => null,
};

int _compareDateTime(Object a, Object b) {
  final ai = _asDateTimeMs(a);
  final bi = _asDateTimeMs(b);
  if (ai == null && bi == null) return 0;
  if (ai == null) return 1;
  if (bi == null) return -1;
  return ai.compareTo(bi);
}

int? _asDateTimeMs(Object value) {
  final DateTime? parsed = switch (value) {
    DateTime d => d,
    int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    num n => DateTime.fromMillisecondsSinceEpoch(n.toInt(), isUtc: true),
    String s => DateTime.tryParse(s),
    _ => null,
  };
  return parsed?.toUtc().millisecondsSinceEpoch;
}

int _compareJson(Object a, Object b) {
  return jsonEncode(a).compareTo(jsonEncode(b));
}
