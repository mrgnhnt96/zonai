import 'package:zonai_schema/zonai_schema.dart';

extension WhereX on Where {
  String sql(String tableName) {
    return WhereSql(tableName, this).toSql();
  }
}

class WhereSql {
  const WhereSql(this.table, this.data);

  factory WhereSql.fromJson(Map<String, dynamic> json) {
    return WhereSql(
      json['table'] as String,
      Where.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  final String table;
  final Where data;

  String toSql([Where? data]) {
    final where = data ?? this.data;

    switch (where) {
      case Eq(:final column, :final value):
        return '"${table}"."${column}" = \'$value\'';

      case Null(:final column):
        return '"${table}"."${column}" IS NULL';

      case NotNull(:final column):
        return '"${table}"."${column}" IS NOT NULL';

      case Gt(:final column, :final value):
        return '"${table}"."${column}" > \'$value\'';

      case Lt(:final column, :final value):
        return '"${table}"."${column}" < \'$value\'';

      case Gte(:final column, :final value):
        return '"${table}"."${column}" >= \'$value\'';

      case Lte(:final column, :final value):
        return '"${table}"."${column}" <= \'$value\'';

      case In(:final column, :final values):
        final placeholders = values.map((e) => '\'$e\'').join(', ');
        return '"${table}"."${column}" IN ($placeholders)';

      case NotIn(:final column, :final values):
        if (values.isEmpty) {
          return '"${table}"."${column}" IS NULL';
        }
        final placeholders = values.map((e) => '\'$e\'').join(', ');
        return '"${table}"."${column}" NOT IN ($placeholders)';

      case Contains(:final column, :final value):
        return '"${table}"."${column}" LIKE \'%$value%\'';

      case StartsWith(:final column, :final value):
        return '"${table}"."${column}" LIKE \'${value}%\'';

      case EndsWith(:final column, :final value):
        return '"${table}"."${column}" LIKE \'%${value}\'';

      case NotContains(:final column, :final value):
        return '"${table}"."${column}" NOT LIKE \'%$value%\'';

      case And(:final conditions):
        if (conditions.isEmpty) {
          return '1 = 1';
        }

        final statements = [
          for (final condition in conditions)
            WhereSql(table, condition).toSql(),
        ];

        return '(${statements.join(' AND ')})';

      case Or(:final conditions):
        if (conditions.isEmpty) {
          return '1 = 1';
        }

        final statements = [
          for (final condition in conditions)
            WhereSql(table, condition).toSql(),
        ];

        return '(${statements.join(' OR ')})';
    }
  }
}
