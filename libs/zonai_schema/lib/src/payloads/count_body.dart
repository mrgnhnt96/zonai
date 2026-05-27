import 'package:zonai_schema/src/types/where.dart';

class CountBody {
  const CountBody({required this.table, this.where});

  factory CountBody.fromJson(Map<String, dynamic> json) {
    return CountBody(
      table: json['table'] as String,
      where: json['where'] != null ? Where.fromJson(json['where']) : null,
    );
  }

  final String table;
  final Where? where;

  Map<String, dynamic> toJson() {
    return {'table': table, 'where': ?where?.toJson()};
  }
}
