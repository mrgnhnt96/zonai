import 'package:zonai/src/db_mutator/payloads/payloads.dart';

extension WhereX on Where {
  String sql(String collection) {
    return WhereSql(collection, this).toSql();
  }
}

class WhereSql {
  const WhereSql(this.collection, this.data);

  factory WhereSql.fromJson(Map<String, dynamic> json) {
    return WhereSql(
      json['collection'] as String,
      Where.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  final String collection;
  final Where data;

  String toSql([Where? data]) {
    final where = data ?? this.data;

    switch (where) {
      case Eq(:final column, :final value):
        return '"${collection}"."${column}" = \'$value\'';

      case Null(:final column):
        return '"${collection}"."${column}" IS NULL';

      case NotNull(:final column):
        return '"${collection}"."${column}" IS NOT NULL';

      case Gt(:final column, :final value):
        return '"${collection}"."${column}" > \'$value\'';

      case Lt(:final column, :final value):
        return '"${collection}"."${column}" < \'$value\'';

      case Gte(:final column, :final value):
        return '"${collection}"."${column}" >= \'$value\'';

      case Lte(:final column, :final value):
        return '"${collection}"."${column}" <= \'$value\'';

      case In(:final column, :final values):
        final placeholders = values.map((e) => '\'$e\'').join(', ');
        return '"${collection}"."${column}" IN ($placeholders)';

      case NotIn(:final column, :final values):
        if (values.isEmpty) {
          return '"${collection}"."${column}" IS NULL';
        }
        final placeholders = values.map((e) => '\'$e\'').join(', ');
        return '"${collection}"."${column}" NOT IN ($placeholders)';

      case And(:final conditions):
        if (conditions.isEmpty) {
          return '1 = 1';
        }

        final statements = [
          for (final condition in conditions)
            WhereSql(collection, condition).toSql(),
        ];

        return '(${statements.join(' AND ')})';

      case Or(:final conditions):
        if (conditions.isEmpty) {
          return '1 = 1';
        }

        final statements = [
          for (final condition in conditions)
            WhereSql(collection, condition).toSql(),
        ];

        return '(${statements.join(' OR ')})';
    }
  }
}
