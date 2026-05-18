import 'package:zonai_schema/zonai_schema.dart';

class DeleteBody {
  const DeleteBody({required this.collection, required this.where, this.limit});

  final String collection;
  final Where where;
  final int? limit;

  factory DeleteBody.fromJson(Map<String, dynamic> json) {
    return DeleteBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      limit: json['limit'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'collection': collection, 'where': where.toJson(), 'limit': limit};
  }
}

class DeleteOneBody extends DeleteBody {
  const DeleteOneBody({required super.collection, required super.where})
    : super(limit: 1);

  factory DeleteOneBody.fromJson(Map<String, dynamic> json) {
    return DeleteOneBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
    );
  }
}
