part of payloads;

sealed class Where {
  const Where();

  factory Where.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      Eq._type => Eq.fromJson(json),
      Null._type => Null.fromJson(json),
      NotNull._type => NotNull.fromJson(json),
      Gt._type => Gt.fromJson(json),
      Gte._type => Gte.fromJson(json),
      Lt._type => Lt.fromJson(json),
      Lte._type => Lte.fromJson(json),
      In._type => In.fromJson(json),
      NotIn._type => NotIn.fromJson(json),
      And._type => And.fromJson(json),
      Or._type => Or.fromJson(json),
      _ => throw ArgumentError.value(
        json['type'],
        'type',
        'Invalid where type',
      ),
    };
  }

  Map<String, Object?> toJson();
}

final class Eq extends Where {
  const Eq(this.column, this.value);

  factory Eq.fromJson(Map<String, dynamic> json) {
    return Eq(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'eq';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': value,
  };
}

final class Null extends Where {
  const Null(this.column);

  factory Null.fromJson(Map<String, dynamic> json) {
    return Null(json['column'] as String);
  }

  final String column;

  static const _type = 'null';

  @override
  Map<String, Object?> toJson() => {'type': _type, 'column': column};
}

final class NotNull extends Where {
  const NotNull(this.column);

  factory NotNull.fromJson(Map<String, dynamic> json) {
    return NotNull(json['column'] as String);
  }

  final String column;

  static const _type = 'not_null';

  @override
  Map<String, Object?> toJson() => {'type': _type, 'column': column};
}

final class Gt extends Where {
  const Gt(this.column, this.value);

  factory Gt.fromJson(Map<String, dynamic> json) {
    return Gt(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'gt';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': value,
  };
}

final class Gte extends Where {
  const Gte(this.column, this.value);

  factory Gte.fromJson(Map<String, dynamic> json) {
    return Gte(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'gte';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': value,
  };
}

final class Lt extends Where {
  const Lt(this.column, this.value);

  factory Lt.fromJson(Map<String, dynamic> json) {
    return Lt(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'lt';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': value,
  };
}

final class Lte extends Where {
  const Lte(this.column, this.value);

  factory Lte.fromJson(Map<String, dynamic> json) {
    return Lte(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'lte';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': value,
  };
}

final class In extends Where {
  const In(this.column, this.values);

  factory In.fromJson(Map<String, dynamic> json) {
    return In(json['column'] as String, json['values'] as List<Object>);
  }

  final String column;
  final List<Object> values;

  static const _type = 'in';
  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'values': values,
  };
}

final class NotIn extends Where {
  const NotIn(this.column, this.values);

  factory NotIn.fromJson(Map<String, dynamic> json) {
    return NotIn(json['column'] as String, json['values'] as List<Object>);
  }

  final String column;
  final List<Object> values;

  static const _type = 'not_in';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'values': values,
  };
}

final class And extends Where {
  const And(this.conditions);

  factory And.fromJson(Map<String, dynamic> json) {
    return And([
      for (final condition in json['conditions'] as List<dynamic>)
        Where.fromJson(condition as Map<String, dynamic>),
    ]);
  }

  final List<Where> conditions;

  static const _type = 'and';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'conditions': conditions.map((e) => e.toJson()).toList(),
  };
}

final class Or extends Where {
  const Or(this.conditions);

  factory Or.fromJson(Map<String, dynamic> json) {
    return Or([
      for (final condition in json['conditions'] as List<dynamic>)
        Where.fromJson(condition as Map<String, dynamic>),
    ]);
  }

  final List<Where> conditions;

  static const _type = 'or';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'conditions': conditions.map((e) => e.toJson()).toList(),
  };
}
