part of update;

sealed class UpdateValue {
  const UpdateValue();
  factory UpdateValue.literal(Object? value) = Literal;
  factory UpdateValue.increment() = Increment;
  factory UpdateValue.decrement() = Decrement;
  factory UpdateValue.add(Object? value) = Add;
  factory UpdateValue.remove(Object? value) = Remove;
  factory UpdateValue.addAll(List<Object?> values) = AddAll;
  factory UpdateValue.removeAll(List<Object?> values) = RemoveAll;

  factory UpdateValue.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      Literal._type => Literal.fromJson(json),
      Increment._type => Increment.fromJson(json),
      Decrement._type => Decrement.fromJson(json),
      Add._type => Add.fromJson(json),
      Remove._type => Remove.fromJson(json),
      AddAll._type => AddAll.fromJson(json),
      RemoveAll._type => RemoveAll.fromJson(json),
      final type => throw StateError('Invalid update value type: $type'),
    };
  }

  String get type;

  @mustCallSuper
  Map<String, dynamic> toJson() {
    return {'type': type};
  }
}

class Literal extends UpdateValue {
  const Literal(this.value);
  factory Literal.fromJson(Map<String, dynamic> json) {
    return Literal(json['value']);
  }

  static const _type = 'literal';

  final Object? value;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'value': jsonDecode(jsonEncode(value))};
  }

  @override
  String get type => _type;
}

class Increment extends UpdateValue {
  const Increment();

  factory Increment.fromJson(Map<String, dynamic> json) {
    return Increment();
  }

  static const _type = 'increment';

  @override
  String get type => _type;
}

class Decrement extends UpdateValue {
  const Decrement();

  factory Decrement.fromJson(Map<String, dynamic> json) {
    return Decrement();
  }

  static const _type = 'decrement';

  @override
  String get type => _type;
}

class Add extends UpdateValue {
  const Add(this.value);
  factory Add.fromJson(Map<String, dynamic> json) {
    return Add(json['value']);
  }

  static const _type = 'add';

  final Object? value;

  @override
  String get type => _type;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'value': jsonDecode(jsonEncode(value))};
  }
}

class Remove extends UpdateValue {
  const Remove(this.value);
  factory Remove.fromJson(Map<String, dynamic> json) {
    return Remove(json['value']);
  }

  static const _type = 'remove';

  final Object? value;

  @override
  String get type => _type;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'value': jsonDecode(jsonEncode(value))};
  }
}

/// Appends every element of [values] to a list column.
class AddAll extends UpdateValue {
  const AddAll(this.values);
  factory AddAll.fromJson(Map<String, dynamic> json) {
    return AddAll(List<Object?>.from(json['values'] as List<dynamic>));
  }

  static const _type = 'add_all';

  final List<Object?> values;

  @override
  String get type => _type;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'values': jsonDecode(jsonEncode(values)) as List<dynamic>,
    };
  }
}

/// Removes every element from a list column that appears in [values]
class RemoveAll extends UpdateValue {
  const RemoveAll(this.values);
  factory RemoveAll.fromJson(Map<String, dynamic> json) {
    return RemoveAll(List<Object?>.from(json['values'] as List<dynamic>));
  }

  static const _type = 'remove_all';

  final List<Object?> values;

  @override
  String get type => _type;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'values': jsonDecode(jsonEncode(values)) as List<dynamic>,
    };
  }
}
