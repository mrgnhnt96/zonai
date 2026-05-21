import '../types/where.dart';

class GetBody {
  const GetBody({
    required this.collection,
    required this.where,
    this.expand = const [],
  });

  final String collection;
  final Where where;
  final List<String> expand;

  factory GetBody.fromJson(Map<String, dynamic> json) {
    return GetBody(
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
