part of payloads;

sealed class UpdateValue {
  const UpdateValue();

  factory UpdateValue.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      LiteralUpdateValue._type => LiteralUpdateValue.fromJson(json),
      final type => throw StateError('Invalid update value type: $type'),
    };
  }

  String get type;

  Map<String, dynamic> toJson();
}

class LiteralUpdateValue extends UpdateValue {
  const LiteralUpdateValue({required this.value});
  factory LiteralUpdateValue.fromJson(Map<String, dynamic> json) {
    return LiteralUpdateValue(value: json['value']);
  }

  static const _type = 'literal';

  final dynamic value;

  @override
  Map<String, dynamic> toJson() {
    return {'type': _type, 'value': value};
  }

  @override
  String get type => _type;
}
