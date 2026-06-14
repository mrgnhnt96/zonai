import 'dart:convert';

import 'package:raindrop/raindrop.dart';

extension MapColumnDefinition<S> on SchemaBuilder<S> {
  /// JSON object as [Map<String, dynamic>], stored in TEXT
  ColumnType<W> map<W extends Map<String, dynamic>?>(
    String name,
    Field<S, W> field, {
    Map<String, dynamic> Function(dynamic) fromJson = _mapFromDynamic,
  }) {
    return custom<Map<String, dynamic>, Object, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: MapTransformer<Map<String, dynamic>>(fromJson: fromJson),
    );
  }

  static Map<String, dynamic> _mapFromDynamic(dynamic d) =>
      Map<String, dynamic>.from(d as Map);

  /// JSON object as [V], stored in TEXT
  ColumnType<W> mapAs<V extends Object, W extends V?>(
    String name,
    Field<S, W> field, {
    required V Function(dynamic) fromJson,
    required V synthetic,
  }) {
    return custom<V, Object, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: MapTransformer<V>(fromJson: fromJson),
    );
  }
}

class MapTransformer<T> extends ColumnTransformer<T, Object> {
  MapTransformer({required this.fromJson});

  final T Function(dynamic) fromJson;

  @override
  String encode(T input) => jsonEncode(input);

  @override
  T decode(Object input) {
    if (input is T) {
      return input as T;
    }
    return fromJson(_decodeToMap(input));
  }
}

Map<String, dynamic> _decodeToMap(Object input) {
  if (input is Map<String, dynamic>) {
    return {...input};
  }

  if (input is Map) {
    return {...input.map((k, v) => MapEntry('$k', v))};
  }

  if (input is String) {
    if (input.isEmpty) {
      return {};
    }

    final decoded = jsonDecode(input);
    if (decoded is! Map) {
      throw ArgumentError.value(
        input,
        'input',
        'Expected a JSON object string, got ${decoded.runtimeType}',
      );
    }

    return {...decoded};
  }

  throw ArgumentError.value(
    input,
    'input',
    'Expected JSON text or Map, got ${input.runtimeType}',
  );
}
