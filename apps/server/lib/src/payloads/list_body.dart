import 'package:zonai/zonai.dart';

class ListBody {
  const ListBody({
    required this.collection,
    this.where,
    this.limit,
    this.offset,
  });

  final String collection;
  final Where? where;
  final int? limit;
  final int? offset;

  factory ListBody.fromJson(Map<String, dynamic> json) {
    return ListBody(
      collection: json['collection'] as String,
      where: json['where'] != null ? Where.fromJson(json['where']) : null,
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collection': collection,
      'where': where?.toJson(),
      'limit': limit,
      'offset': offset,
    };
  }
}
