import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: $json');
    }

    return switch (parts[1]) {
      ItemsId._suffix => ItemsId(json),
      UsersId._suffix => UsersId(json),
      _ => throw ArgumentError('Invalid ID format: $json'),
    };
  }

  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is Id && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class ItemsId extends Id {
  const ItemsId(super.value);

  factory ItemsId.generate() => ItemsId(z.Id.generate(_suffix));

  static const _suffix = 'it';
}

class UsersId extends Id {
  const UsersId(super.value);

  factory UsersId.generate() => UsersId(z.Id.generate(_suffix));

  static const _suffix = 'us';
}
