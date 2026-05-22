import 'package:zonai_schema/src/types/where.dart';

class CountBody {
  const CountBody({required this.collection, this.where});

  factory CountBody.fromJson(Map<String, dynamic> json) {
    return CountBody(
      collection: json['collection'] as String,
      where: json['where'] != null ? Where.fromJson(json['where']) : null,
    );
  }

  final String collection;
  final Where? where;

  Map<String, dynamic> toJson() {
    return {'collection': collection, 'where': ?where?.toJson()};
  }
}
