import 'dart:convert';

import 'where_value.dart';

sealed class Where {
  const Where();

  factory Where.fromJson(Map json) {
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
      Contains._type => Contains.fromJson(json),
      NotContains._type => NotContains.fromJson(json),
      StartsWith._type => StartsWith.fromJson(json),
      EndsWith._type => EndsWith.fromJson(json),
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

  factory Eq.fromJson(Map json) {
    return Eq(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'eq';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class Null extends Where {
  const Null(this.column);

  factory Null.fromJson(Map json) {
    return Null(json['column'] as String);
  }

  final String column;

  static const _type = 'is_null';

  @override
  Map<String, Object?> toJson() => {'type': _type, 'column': column};
}

final class NotNull extends Where {
  const NotNull(this.column);

  factory NotNull.fromJson(Map json) {
    return NotNull(json['column'] as String);
  }

  final String column;

  static const _type = 'not_null';

  @override
  Map<String, Object?> toJson() => {'type': _type, 'column': column};
}

final class Gt extends Where {
  const Gt(this.column, this.value);

  factory Gt.fromJson(Map json) {
    return Gt(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'gt';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class Gte extends Where {
  const Gte(this.column, this.value);

  factory Gte.fromJson(Map json) {
    return Gte(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'gte';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class Lt extends Where {
  const Lt(this.column, this.value);

  factory Lt.fromJson(Map json) {
    return Lt(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'lt';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class Lte extends Where {
  const Lte(this.column, this.value);

  factory Lte.fromJson(Map json) {
    return Lte(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'lte';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class In extends Where {
  const In(this.column, this.values);

  factory In.fromJson(Map json) {
    return In(
      json['column'] as String,
      switch (json['values']) {
        final String s => [serializeWhereValue(jsonDecode(s) as Object)],
        final List list => [
          for (final value in list) serializeWhereValue(value),
        ],
        _ => throw ArgumentError.value(
          json['values'],
          'values',
          'Expected a string or list',
        ),
      },
    );
  }

  final String column;
  final List<Object> values;

  static const _type = 'in';
  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'values': serializeWhereValues(values),
  };
}

final class NotIn extends Where {
  const NotIn(this.column, this.values);

  factory NotIn.fromJson(Map json) {
    return NotIn(
      json['column'] as String,
      switch (json['values']) {
        final String s => [serializeWhereValue(jsonDecode(s) as Object)],
        final List list => [
          for (final value in list) serializeWhereValue(value),
        ],
        _ => throw ArgumentError.value(
          json['values'],
          'values',
          'Expected a string or list',
        ),
      },
    );
  }

  final String column;
  final List<Object> values;

  static const _type = 'not_in';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'values': serializeWhereValues(values),
  };
}

final class And extends Where {
  const And(this.conditions);

  factory And.fromJson(Map json) {
    return And([
      for (final condition in json['conditions'] as List<dynamic>)
        Where.fromJson(condition as Map),
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

  factory Or.fromJson(Map json) {
    return Or([
      for (final condition in json['conditions'] as List<dynamic>)
        Where.fromJson(condition as Map),
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

final class Contains extends Where {
  const Contains(this.column, this.value);

  factory Contains.fromJson(Map json) {
    return Contains(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'contains';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class StartsWith extends Where {
  const StartsWith(this.column, this.value);

  factory StartsWith.fromJson(Map json) {
    return StartsWith(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'starts_with';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class EndsWith extends Where {
  const EndsWith(this.column, this.value);

  factory EndsWith.fromJson(Map json) {
    return EndsWith(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'ends_with';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}

final class NotContains extends Where {
  const NotContains(this.column, this.value);

  factory NotContains.fromJson(Map json) {
    return NotContains(json['column'] as String, json['value'] as Object);
  }

  final String column;
  final Object value;

  static const _type = 'not_contains';

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'column': column,
    'value': serializeWhereValue(value),
  };
}
