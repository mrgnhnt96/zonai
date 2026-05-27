import '../types/order_by.dart';
import '../types/where.dart';

class StreamListBody {
  const StreamListBody({
    required this.table,
    this.where,
    this.limit,
    this.offset,
    this.orderBy,
    this.expand = const [],
  });

  final String table;
  final Where? where;
  final int? limit;
  final int? offset;
  final List<OrderByTerm>? orderBy;
  final List<String> expand;

  factory StreamListBody.fromJson(Map<String, dynamic> json) {
    return StreamListBody(
      table: json['table'] as String,
      where: json['where'] != null ? Where.fromJson(json['where']) : null,
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      orderBy: switch (json['order_by']) {
        null => null,
        final List list => [
          for (final item in list)
            OrderByTerm.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        final value => throw ArgumentError.value(
          value,
          'order_by',
          'Expected a list of order terms',
        ),
      },
      expand: json['expand'] as List<String>? ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'table': table,
      'where': ?where?.toJson(),
      'limit': ?limit,
      'offset': ?offset,
      'order_by': ?switch (orderBy) {
        null => null,
        final terms when terms.isNotEmpty => [
          for (final term in terms) term.toJson(),
        ],
        _ => null,
      },
      'expand': expand,
    };
  }
}
