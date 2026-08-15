import 'package:zonai_schema/payloads.dart';

/// Filter operators exposed in the table search UI (maps to [Where] variants).
enum TableWhereOperator {
  eq,
  null_,
  notNull,
  gt,
  gte,
  lt,
  lte,
  in_,
  notIn,
  contains,
  notContains,
  startsWith,
  endsWith,
}

extension TableWhereOperatorX on TableWhereOperator {
  String get label => switch (this) {
    .eq => '=',
    .null_ => 'is empty',
    .notNull => 'is not empty',
    .gt => '>',
    .gte => '≥',
    .lt => '<',
    .lte => '≤',
    .in_ => 'in',
    .notIn => 'not in',
    .contains => 'contains',
    .notContains => 'does not contain',
    .startsWith => 'starts with',
    .endsWith => 'ends with',
  };

  String get tooltip => switch (this) {
    .eq => 'Equals',
    .null_ => 'Is null',
    .notNull => 'Is not null',
    .gt => 'Greater than',
    .gte => 'Greater than or equal',
    .lt => 'Less than',
    .lte => 'Less than or equal',
    .in_ => 'In list',
    .notIn => 'Not in list',
    .contains => 'Contains',
    .notContains => 'Does not contain',
    .startsWith => 'Starts with',
    .endsWith => 'Ends with',
  };

  bool get needsValue => switch (this) {
    .null_ || .notNull => false,
    _ => true,
  };

  bool get needsListValue => switch (this) {
    .in_ || .notIn => true,
    _ => false,
  };
}

/// Operators available for a column based on its [ColumnShapeKind].
List<TableWhereOperator> operatorsForColumn(ColumnShape shape) {
  return switch (shape.kind) {
    .text || .email || .id => const [.eq, .contains, .startsWith, .endsWith, .notContains, .null_, .notNull],
    // A device token is opaque: no prefix, suffix or substring of one means
    // anything, so offering `starts with` would invite filters that can only
    // ever match by accident. Equality is for finding one known token;
    // `is null` / `is not null` is the filter that actually gets used, since
    // a null token is what pruning leaves behind.
    .deviceToken => const [.eq, .null_, .notNull],
    .integer ||
    .real ||
    .bigInt ||
    .dateTime ||
    .createdAt ||
    .updatedAt => const [.eq, .gt, .gte, .lt, .lte, .null_, .notNull],
    .boolean || .isVerified => const [.eq, .null_, .notNull],
    .enum_ => const [.eq, .in_, .notIn, .null_, .notNull],
    .password || .photo || .photos || .blob || .map || .list || .enumList => const [.eq, .contains, .null_, .notNull],
  };
}

ColumnShape? resolveColumnShape(String columnInput, List<ColumnShape> shapes) {
  final trimmed = columnInput.trim();
  if (trimmed.isEmpty) return null;

  for (final shape in shapes) {
    if (shape.name == trimmed) return shape;
  }
  return null;
}
