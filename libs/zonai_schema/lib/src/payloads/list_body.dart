import '../types/order_by.dart';
import '../types/where.dart';

class ListBody {
  const ListBody({
    required this.table,
    this.where,
    this.limit,
    this.offset,
    this.orderBy,
    this.expand = const [],
  });

  final String table;
  final Where? where;
  final List<String> expand;
  final int? limit;
  final int? offset;
  final List<OrderByTerm>? orderBy;

  factory ListBody.fromJson(Map json) {
    return ListBody(
      table: json['table'] as String,
      where: switch (json['where']) {
        null => null,
        final Map m => Where.fromJson(m),
        final value => throw ArgumentError.value(value, 'where', 'Expected a where object'),
      },
      limit: json['limit'] as int?,
      offset: json['offset'] as int?,
      orderBy: switch (json['order_by']) {
        null => null,
        final List list => [
          for (final item in list) OrderByTerm.fromJson(Map.from(item as Map)),
        ],
        final value => throw ArgumentError.value(
          value,
          'order_by',
          'Expected a list of order terms',
        ),
      },
      expand: [
        if (json['expand'] case final List list)
          for (final item in list) item as String,
      ],
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
