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
      total: json['total'] as int,
    );
  }

  final List<T> items;
  final int total;

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => jsonDecode(jsonEncode(e))).toList(),
      'total': total,
    };
  }
}
