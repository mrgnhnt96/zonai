import '../types/where.dart';

class StreamListBody {
  const StreamListBody({
    required this.collection,
    this.where,
    this.limit,
    this.offset,
  });

  final String collection;
  final Where? where;
  final int? limit;
  final int? offset;

  factory StreamListBody.fromJson(Map<String, dynamic> json) {
    return StreamListBody(
      collection: json['collection'] as String,
      where: json['where'] != null ? Where.fromJson(json['where']) : null,
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collection': collection,
      'where': ?where?.toJson(),
      'limit': ?limit,
      'offset': ?offset,
    };
  }
}
