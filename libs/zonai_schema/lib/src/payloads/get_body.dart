import '../types/where.dart';
import 'package:zonai_schema/src/payloads/parse_body.dart';

class GetBody {
  const GetBody({
    required this.table,
    required this.where,
    this.expand = const [],
  });

  final String table;
  final Where where;
  final List<String> expand;

  factory GetBody.fromJson(Map<String, dynamic> json) =>
      parseBody('GetBody', () => GetBody._fromJson(json));

  factory GetBody._fromJson(Map<String, dynamic> json) {
    return GetBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map),
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
