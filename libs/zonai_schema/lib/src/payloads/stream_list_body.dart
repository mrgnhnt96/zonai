import '../types/where.dart';

class StreamListBody {
  const StreamListBody({
    required this.collection,
    this.where,
    this.limit,
    this.offset,
    this.expand = const [],
  });

  final String collection;
  final Where? where;
  final int? limit;
  final int? offset;
  final List<String> expand;

  factory StreamListBody.fromJson(Map<String, dynamic> json) {
    return StreamListBody(
      collection: json['collection'] as String,
      where: json['where'] != null ? Where.fromJson(json['where']) : null,
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      expand: json['expand'] as List<String>? ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collection': collection,
      'where': ?where?.toJson(),
      'limit': ?limit,
      'offset': ?offset,
      'expand': expand,
    };
  }
}
