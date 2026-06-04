import 'package:zonai_schema/src/types/where.dart';

class CountBody {
  const CountBody({required this.table, this.where});

  factory CountBody.fromJson(Map<String, dynamic> json) {
    return CountBody(
      table: json['table'] as String,
      where: switch (json['where']) {
        null => null,
        final Map m => Where.fromJson(m),
        final value => throw ArgumentError.value(
          value,
          'where',
          'Expected a where object',
        ),
      },
    );
  }

  final String table;
  final Where? where;

  Map<String, dynamic> toJson() {
    return {'table': table, 'where': ?where?.toJson()};
  }
}
