import 'package:zonai_schema/payloads.dart';

import 'table_cell_edit.dart';
import 'table_where_operators.dart';

enum FilterCombine { and, or }

/// One row in the search panel before Apply.
final class FilterConditionDraft {
  const FilterConditionDraft({
    this.columnName = '',
    this.operator,
    this.valueText = '',
    this.boolValue = true,
    this.dateTimeUseUtc = false,
  });

  final String columnName;
  final TableWhereOperator? operator;
  final String valueText;
  final bool boolValue;

  /// When true, filter datetime presets and picker use UTC wall time (not local).
  final bool dateTimeUseUtc;

  FilterConditionDraft copyWith({
    String? columnName,
    TableWhereOperator? operator,
    String? valueText,
    bool? boolValue,
    bool? dateTimeUseUtc,
    bool clearOperator = false,
  }) {
    return FilterConditionDraft(
      columnName: columnName ?? this.columnName,
      operator: clearOperator ? null : (operator ?? this.operator),
      valueText: valueText ?? this.valueText,
      boolValue: boolValue ?? this.boolValue,
      dateTimeUseUtc: dateTimeUseUtc ?? this.dateTimeUseUtc,
    );
  }
}

/// Default draft for a new filter row: first column and its first operator.
FilterConditionDraft defaultFilterConditionDraft(List<ColumnShape> columnShapes) {
  if (columnShapes.isEmpty) return const FilterConditionDraft();
  return draftForColumn(columnShapes.first.name, columnShapes);
}

/// Draft for a chosen column with the first allowed operator selected.
FilterConditionDraft draftForColumn(String columnName, List<ColumnShape> columnShapes) {
  final shape = resolveColumnShape(columnName, columnShapes);
  if (shape == null) {
    return FilterConditionDraft(columnName: columnName.trim());
  }
  final operators = operatorsForColumn(shape);
  return FilterConditionDraft(
    columnName: shape.name,
    operator: operators.isEmpty ? null : operators.first,
  );
}

/// Fills missing column/operator on an in-progress draft row.
FilterConditionDraft ensureDraftDefaults(FilterConditionDraft row, List<ColumnShape> columnShapes) {
  if (columnShapes.isEmpty) return row;
  if (row.columnName.isEmpty) return defaultFilterConditionDraft(columnShapes);
  if (row.operator != null) return row;
  final shape = resolveColumnShape(row.columnName, columnShapes);
  if (shape == null) return row;
  final operators = operatorsForColumn(shape);
  if (operators.isEmpty) return row;
  return row.copyWith(operator: operators.first);
}

/// Result of validating and building a [Where] from draft rows.
sealed class TableWhereBuildResult {}

final class TableWhereBuildSuccess extends TableWhereBuildResult {
  TableWhereBuildSuccess(this.where);

  final Where where;
}

final class TableWhereBuildError extends TableWhereBuildResult {
  TableWhereBuildError(this.message);

  final String message;
}

/// Builds a [Where] from draft filter rows, or reports validation errors.
TableWhereBuildResult buildWhereFromDraft({
  required List<FilterConditionDraft> rows,
  required FilterCombine combine,
  required List<ColumnShape> columnShapes,
}) {
  final conditions = <Where>[];

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final shape = resolveColumnShape(row.columnName, columnShapes);
    if (shape == null) {
      return TableWhereBuildError('Row ${i + 1}: choose a valid column.');
    }
    final op = row.operator;
    if (op == null) {
      return TableWhereBuildError('Row ${i + 1}: choose an operator.');
    }
    final allowed = operatorsForColumn(shape);
    if (!allowed.contains(op)) {
      return TableWhereBuildError('Row ${i + 1}: operator not allowed for ${shape.name}.');
    }

    try {
      final where = _buildCondition(shape: shape, operator: op, row: row);
      conditions.add(where);
    } on FormatException catch (e) {
      return TableWhereBuildError('Row ${i + 1}: ${e.message}');
    }
  }

  if (conditions.isEmpty) {
    return TableWhereBuildError('Add at least one filter condition.');
  }

  if (conditions.length == 1) {
    return TableWhereBuildSuccess(conditions.single);
  }

  return TableWhereBuildSuccess(
    switch (combine) {
      FilterCombine.and => And(conditions),
      FilterCombine.or => Or(conditions),
    },
  );
}

Where _buildCondition({
  required ColumnShape shape,
  required TableWhereOperator operator,
  required FilterConditionDraft row,
}) {
  final column = shape.name;

  return switch (operator) {
    TableWhereOperator.null_ => Null(column),
    TableWhereOperator.notNull => NotNull(column),
    TableWhereOperator.eq => Eq(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.gt => Gt(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.gte => Gte(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.lt => Lt(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.lte => Lte(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.in_ => In(column, _parseListValues(shape: shape, row: row)),
    TableWhereOperator.notIn => NotIn(column, _parseListValues(shape: shape, row: row)),
    TableWhereOperator.contains => Contains(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.notContains => NotContains(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.startsWith => StartsWith(column, _parseSingleValue(shape: shape, row: row)),
    TableWhereOperator.endsWith => EndsWith(column, _parseSingleValue(shape: shape, row: row)),
  };
}

Object _parseSingleValue({required ColumnShape shape, required FilterConditionDraft row}) {
  if (shape.kind == ColumnShapeKind.boolean || shape.kind == ColumnShapeKind.isVerified) {
    return row.boolValue;
  }

  final trimmed = row.valueText.trim();
  if (trimmed.isEmpty) {
    throw FormatException('Enter a value for ${shape.name}.');
  }

  final parsed = parseFilterValue(shape: shape, text: trimmed);
  if (parsed == null) {
    throw FormatException('Enter a value for ${shape.name}.');
  }
  return parsed;
}

List<Object> _parseListValues({required ColumnShape shape, required FilterConditionDraft row}) {
  final parts = row.valueText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) {
    throw FormatException('Enter comma-separated values for ${shape.name}.');
  }

  return [
    for (final part in parts)
      parseFilterValue(shape: shape, text: part) ?? (throw FormatException('Invalid value: $part')),
  ];
}

/// Parses filter input for a column (shared with cell edit rules where possible).
Object? parseFilterValue({required ColumnShape shape, required String text}) {
  if (shape.kind == ColumnShapeKind.boolean || shape.kind == ColumnShapeKind.isVerified) {
    return parseEditValue(draftValue: null, textInput: text, shape: shape);
  }

  if (shape.kind == ColumnShapeKind.createdAt ||
      shape.kind == ColumnShapeKind.updatedAt ||
      shape.kind == ColumnShapeKind.dateTime) {
    return _parseDateTimeForFilter(text);
  }

  return parseEditValue(draftValue: null, textInput: text, shape: shape);
}

DateTime _parseDateTimeForFilter(String text) {
  if (RegExp(r'^\d+$').hasMatch(text)) {
    return DateTime.fromMillisecondsSinceEpoch(int.parse(text), isUtc: true);
  }

  final normalized = text.endsWith(' UTC') ? text.replaceFirst(' UTC', 'Z') : text;
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) {
    throw FormatException('Invalid date/time; use YYYY-MM-DD HH:MM:SS UTC or milliseconds');
  }
  return parsed.isUtc ? parsed : parsed.toUtc();
}

/// Human-readable summary of an applied [Where] for the table subtitle.
String describeAppliedWhere(Where where, List<ColumnShape> shapes) {
  return switch (where) {
    And(:final conditions) => conditions.map((c) => _describeCondition(c, shapes)).join(' AND '),
    Or(:final conditions) => conditions.map((c) => _describeCondition(c, shapes)).join(' OR '),
    _ => _describeCondition(where, shapes),
  };
}

String _describeWhereValue(Object value, String column, List<ColumnShape> shapes) {
  if (value is! DateTime) return '$value';
  final shape = _shapeForColumn(column, shapes);
  if (shape == null || !isDateTimeColumnKind(shape.kind)) return '$value';
  return cellToEditString(value, shape);
}

ColumnShape? _shapeForColumn(String column, List<ColumnShape> shapes) {
  for (final shape in shapes) {
    if (shape.name == column) return shape;
  }
  return null;
}

String _describeCondition(Where where, List<ColumnShape> shapes) {
  return switch (where) {
    Eq(:final column, :final value) => '$column = ${_describeWhereValue(value, column, shapes)}',
    Null(:final column) => '$column is empty',
    NotNull(:final column) => '$column is not empty',
    Gt(:final column, :final value) => '$column > ${_describeWhereValue(value, column, shapes)}',
    Gte(:final column, :final value) => '$column ≥ ${_describeWhereValue(value, column, shapes)}',
    Lt(:final column, :final value) => '$column < ${_describeWhereValue(value, column, shapes)}',
    Lte(:final column, :final value) => '$column ≤ ${_describeWhereValue(value, column, shapes)}',
    In(:final column, :final values) => '$column in (${values.join(', ')})',
    NotIn(:final column, :final values) => '$column not in (${values.join(', ')})',
    Contains(:final column, :final value) => '$column contains $value',
    NotContains(:final column, :final value) => '$column does not contain $value',
    StartsWith(:final column, :final value) => '$column starts with $value',
    EndsWith(:final column, :final value) => '$column ends with $value',
    And(:final conditions) => '(${conditions.map((c) => _describeCondition(c, shapes)).join(' AND ')})',
    Or(:final conditions) => '(${conditions.map((c) => _describeCondition(c, shapes)).join(' OR ')})',
  };
}

/// Reconstructs draft rows from an applied [Where] (for panel re-open).
List<FilterConditionDraft> draftsFromWhere(Where where) {
  return switch (where) {
    And(:final conditions) || Or(:final conditions) => [
      for (final c in conditions) ...draftsFromWhere(c),
    ],
    _ => [_draftFromSingleWhere(where)],
  };
}

FilterCombine combineFromWhere(Where where) {
  return switch (where) {
    Or() => FilterCombine.or,
    And() => FilterCombine.and,
    _ => FilterCombine.and,
  };
}

FilterConditionDraft _draftFromSingleWhere(Where where) {
  return switch (where) {
    Eq(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.eq,
      valueText: '$value',
      boolValue: value == true,
    ),
    Null(:final column) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.null_,
    ),
    NotNull(:final column) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.notNull,
    ),
    Gt(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.gt,
      valueText: '$value',
    ),
    Gte(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.gte,
      valueText: '$value',
    ),
    Lt(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.lt,
      valueText: '$value',
    ),
    Lte(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.lte,
      valueText: '$value',
    ),
    In(:final column, :final values) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.in_,
      valueText: values.join(', '),
    ),
    NotIn(:final column, :final values) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.notIn,
      valueText: values.join(', '),
    ),
    Contains(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.contains,
      valueText: '$value',
    ),
    NotContains(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.notContains,
      valueText: '$value',
    ),
    StartsWith(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.startsWith,
      valueText: '$value',
    ),
    EndsWith(:final column, :final value) => FilterConditionDraft(
      columnName: column,
      operator: TableWhereOperator.endsWith,
      valueText: '$value',
    ),
    And(:final conditions) || Or(:final conditions) => FilterConditionDraft(
      columnName: conditions.isNotEmpty ? _draftFromSingleWhere(conditions.first).columnName : '',
    ),
  };
}
