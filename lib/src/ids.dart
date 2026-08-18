import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: $json');
    }

    return switch (parts[1]) {
      AdminsId._suffix => AdminsId(json),
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

class AdminsId extends Id {
  AdminsId(String value)
    : assert(() {
        final parts = value.split('_');
        return parts.length == 2 && parts[1] == _suffix;
      }(), 'Expected an ID with suffix $_suffix, got $value'),
      super(value);

  factory AdminsId.generate() => AdminsId(z.Id.generate(_suffix));

  static const _suffix = 'ad';
}
