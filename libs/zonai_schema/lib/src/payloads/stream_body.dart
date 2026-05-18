import '../types/where.dart';

class StreamBody {
  const StreamBody({required this.collection, required this.where});

  final String collection;
  final Where where;

  factory StreamBody.fromJson(Map<String, dynamic> json) {
    return StreamBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {'collection': collection, 'where': where.toJson()};
  }
}
