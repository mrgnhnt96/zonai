import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai/zonai.dart';

class UpdateBody {
  const UpdateBody({
    required this.collection,
    required this.where,
    this.limit,
    required this.updates,
  });

  final String collection;
  final Where where;
  final int? limit;
  final List<Update> updates;

  factory UpdateBody.fromJson(Map<String, dynamic> json) {
    return UpdateBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      limit: json['limit'] as int?,
      updates: [
        for (final update in json['updates'] as List<dynamic>)
          Update.fromJson(update as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {'collection': collection, 'where': where.toJson(), 'limit': limit};
  }
}

class UpdateOneBody extends UpdateBody {
  const UpdateOneBody({
    required super.collection,
    required super.where,
    required super.updates,
  }) : super(limit: 1);

  factory UpdateOneBody.fromJson(Map<String, dynamic> json) {
    return UpdateOneBody(
      collection: json['collection'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      updates: [
        for (final update in json['updates'] as List<dynamic>)
          Update.fromJson(update as Map<String, dynamic>),
      ],
    );
  }
}
