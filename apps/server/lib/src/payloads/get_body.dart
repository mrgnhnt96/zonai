import 'package:zonai_schema/zonai_schema.dart';

class GetBody {
  const GetBody({required this.collection, required this.where});

  final String collection;
  final Where where;

  factory GetBody.fromJson(Map<String, dynamic> json) {
    return GetBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {'collection': collection, 'where': where.toJson()};
  }
}
