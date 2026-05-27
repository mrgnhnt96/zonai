import '../types/where.dart';

class StreamCountBody {
  const StreamCountBody({required this.table, required this.where});

  final String table;
  final Where where;

  factory StreamCountBody.fromJson(Map<String, dynamic> json) {
    return StreamCountBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {'table': table, 'where': where.toJson()};
  }
}
