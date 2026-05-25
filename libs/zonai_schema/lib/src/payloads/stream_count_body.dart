import '../types/where.dart';

class StreamCountBody {
  const StreamCountBody({required this.collection, required this.where});

  final String collection;
  final Where where;

  factory StreamCountBody.fromJson(Map<String, dynamic> json) {
    return StreamCountBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {'collection': collection, 'where': where.toJson()};
  }
}
