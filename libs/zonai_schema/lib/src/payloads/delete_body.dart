import '../types/where.dart';

class DeleteBody {
  const DeleteBody({required this.table, required this.where, this.limit});

  final String table;
  final Where where;
  final int? limit;

  factory DeleteBody.fromJson(Map<String, dynamic> json) {
    return DeleteBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      limit: json['limit'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'table': table, 'where': where.toJson(), 'limit': limit};
  }
}

class DeleteOneBody extends DeleteBody {
  const DeleteOneBody({required super.table, required super.where})
    : super(limit: 1);

  factory DeleteOneBody.fromJson(Map<String, dynamic> json) {
    return DeleteOneBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
    );
  }
}
