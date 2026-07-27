import 'package:zonai_schema/zonai_schema.dart';

import 'where_value.dart';

extension WhereX on Where {
  /// Renders this [Where] to a parameterized SQL fragment.
  ///
  /// [tableName] qualifies every column reference (`"table"."column"`).
  /// Pass `null` for an unqualified reference (`"column"`) — required when
  /// there's no single table name to qualify with, e.g. a view's query
  /// joining multiple tables, where columns must resolve by name against
  /// the joined `FROM`/`JOIN` clauses instead.
  (String, List<Object?>) sql(String? tableName) {
    return WhereSql(tableName, this).toSql();
  }
}

class WhereSql {
  const WhereSql(this.table, this.data);

  factory WhereSql.fromJson(Map<String, dynamic> json) {
    return WhereSql(
      json['table'] as String?,
      Where.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  /// Qualifies every column reference when set; unqualified otherwise.
  final String? table;
  final Where data;

  (String, List<Object?>) toSql([Where? data]) {
    final params = <Object?>[];
    final sql = _build(data ?? this.data, params);
    return (sql, params);
  }

  String _col(String column) => switch (table) {
    null => '"${_esc(column)}"',
    final table => '"${_esc(table)}"."${_esc(column)}"',
  };

  String _build(Where where, List<Object?> params) {
    switch (where) {
      case Eq(:final column, :final value):
        params.add(whereValueToParam(value));
        return '${_col(column)} = ?';

      case Null(:final column):
        return '${_col(column)} IS NULL';

      case NotNull(:final column):
        return '${_col(column)} IS NOT NULL';

      case Gt(:final column, :final value):
        params.add(whereValueToParam(value));
        return '${_col(column)} > ?';

      case Lt(:final column, :final value):
        params.add(whereValueToParam(value));
        return '${_col(column)} < ?';

      case Gte(:final column, :final value):
        params.add(whereValueToParam(value));
        return '${_col(column)} >= ?';

      case Lte(:final column, :final value):
        params.add(whereValueToParam(value));
        return '${_col(column)} <= ?';

      case In(:final column, :final values):
        if (values.isEmpty) return '1 = 0';
        params.addAll(values.map(whereValueToParam));
        return '${_col(column)} IN (${List.filled(values.length, '?').join(', ')})';

      case NotIn(:final column, :final values):
        if (values.isEmpty) return '${_col(column)} IS NULL';
        params.addAll(values.map(whereValueToParam));
        return '${_col(column)} NOT IN (${List.filled(values.length, '?').join(', ')})';

      case Contains(:final column, :final value):
        params.add('%$value%');
        return '${_col(column)} LIKE ?';

      case StartsWith(:final column, :final value):
        params.add('$value%');
        return '${_col(column)} LIKE ?';

      case EndsWith(:final column, :final value):
        params.add('%$value');
        return '${_col(column)} LIKE ?';

      case NotContains(:final column, :final value):
        params.add('%$value%');
        return '${_col(column)} NOT LIKE ?';

      case And(:final conditions):
        if (conditions.isEmpty) return '1 = 1';
        return '(${[for (final c in conditions) _build(c, params)].join(' AND ')})';

      case Or(:final conditions):
        if (conditions.isEmpty) return '1 = 1';
        return '(${[for (final c in conditions) _build(c, params)].join(' OR ')})';
    }
  }
}

String _esc(String id) => id.replaceAll('"', '""');
