import 'dart:convert';

class Paginated<T> {
  const Paginated({required this.items, required this.total});

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return Paginated(
      items: (json['items'] as List<dynamic>)
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int?,
    );
  }

  final List<T> items;

  /// How many rows match in all, or `null` when the server did not count
  /// them: a caller who needs per-row checks on a table whose row rules
  /// declare no `viewScope` gets the page without a total, because counting
  /// honestly would mean reading every matching row.
  final int? total;

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => jsonDecode(jsonEncode(e))).toList(),
      'total': ?total,
    };
  }
}
