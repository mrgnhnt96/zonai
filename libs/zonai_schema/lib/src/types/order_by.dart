enum SortDirection {
  asc,
  desc;

  factory SortDirection.fromJson(String value) {
    return switch (value) {
      'asc' => SortDirection.asc,
      'desc' => SortDirection.desc,
      _ => throw ArgumentError.value(
        value,
        'direction',
        'Invalid sort direction',
      ),
    };
  }

  String toJson() => name;
}

class OrderByTerm {
  const OrderByTerm({required this.column, this.direction = SortDirection.asc});

  final String column;
  final SortDirection direction;

  factory OrderByTerm.fromJson(Map json) {
    return OrderByTerm(
      column: json['column'] as String,
      direction: json['direction'] != null
          ? SortDirection.fromJson(json['direction'] as String)
          : SortDirection.asc,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'column': column,
      if (direction != SortDirection.asc) 'direction': direction.toJson(),
    };
  }
}
