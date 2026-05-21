import '../types/where.dart';

class StreamBody {
  const StreamBody({
    required this.collection,
    required this.where,
    this.expand = const [],
  });

  final String collection;
  final Where where;
  final List<String> expand;

  factory StreamBody.fromJson(Map<String, dynamic> json) {
    return StreamBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      expand: json['expand'] as List<String>? ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collection': collection,
      'where': where.toJson(),
      'expand': expand,
    };
  }
}
