library update;

part 'update_value.dart';

sealed class Update {
  const Update();

  factory Update.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      ColumnUpdate._type => ColumnUpdate.fromJson(json),
      ObjectUpdate._type => ObjectUpdate.fromJson(json),
      final type => throw StateError('Invalid update type: $type'),
    };
  }

  String get type;

  Map<String, dynamic> toJson();
}

class ColumnUpdate extends Update {
  const ColumnUpdate(this.column, this.value);
  factory ColumnUpdate.fromJson(Map<String, dynamic> json) {
    return ColumnUpdate(
      json['column'] as String,
      UpdateValue.fromJson(json['value'] as Map<String, dynamic>),
    );
  }

  static const _type = 'column';

  final String column;
  final UpdateValue value;

  @override
  Map<String, dynamic> toJson() {
    return {'type': _type, 'column': column, 'value': value.toJson()};
  }

  @override
  String get type => _type;
}

class ObjectUpdate extends Update {
  const ObjectUpdate(this.object);
  factory ObjectUpdate.fromJson(Map<String, dynamic> json) {
    return ObjectUpdate(json['object'] as Map<String, dynamic>);
  }

  static const _type = 'object';

  final Map<String, dynamic> object;

  @override
  Map<String, dynamic> toJson() {
    return {'type': _type, 'object': object};
  }

  @override
  String get type => _type;
}
