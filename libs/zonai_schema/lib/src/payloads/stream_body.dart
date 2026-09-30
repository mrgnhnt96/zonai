import '../types/where.dart';
import 'package:zonai_schema/src/payloads/parse_body.dart';

class StreamBody {
  const StreamBody({
    required this.table,
    required this.where,
    this.expand = const [],
  });

  final String table;
  final Where where;
  final List<String> expand;

  factory StreamBody.fromJson(Map<String, dynamic> json) =>
      parseBody('StreamBody', () => StreamBody._fromJson(json));

  factory StreamBody._fromJson(Map<String, dynamic> json) {
    return StreamBody(
      table: json['table'] as String,
      where: Where.fromJson(Map<String, dynamic>.from(json['where'] as Map)),
      expand: [
        if (json['expand'] case final List list)
          for (final item in list) item as String,
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {'table': table, 'where': where.toJson(), 'expand': expand};
  }
}
