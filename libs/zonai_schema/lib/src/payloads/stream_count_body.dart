import '../types/where.dart';
import 'package:zonai_schema/src/payloads/parse_body.dart';

class StreamCountBody {
  const StreamCountBody({required this.table, required this.where});

  final String table;
  final Where where;

  factory StreamCountBody.fromJson(Map<String, dynamic> json) =>
      parseBody('StreamCountBody', () => StreamCountBody._fromJson(json));

  factory StreamCountBody._fromJson(Map<String, dynamic> json) {
    return StreamCountBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {'table': table, 'where': where.toJson()};
  }
}
