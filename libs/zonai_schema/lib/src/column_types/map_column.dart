import 'dart:convert';

import 'package:raindrop/raindrop.dart';

/// JSON object as [Map<String, dynamic>], stored in TEXT
extension type MapColumn(Map<String, dynamic> _)
    implements ColumnType<Map<String, dynamic>>, Map<String, dynamic> {}

/// JSON object as [T], stored in TEXT
extension type TypedMapColumn<T>(T _) implements ColumnType<T> {}

extension MapColumnDefinition<S> on SchemaBuilder<S> {
  /// JSON object as [Map<String, dynamic>], stored in TEXT
  T map<T extends MapColumn?, W extends Object?>(
    String name,
    Field<S, W> field, {
    Map<String, dynamic> Function(dynamic) fromJson = _mapFromDynamic,
  }) {
    return custom<MapColumn, Map<String, dynamic>, Object, W>(
          MapColumn.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: MapTransformer<Map<String, dynamic>>(fromJson: fromJson),
          synthetic: {},
        )
        as T;
  }

  static Map<String, dynamic> _mapFromDynamic(dynamic d) =>
      Map<String, dynamic>.from(d as Map);

  /// JSON object as [V], stored in TEXT
  T mapAs<V extends Object, T extends TypedMapColumn<V>?, W extends Object?>(
    String name,
    Field<S, W> field, {
    required V Function(dynamic) fromJson,
    required V synthetic,
  }) {
    return custom<TypedMapColumn<V>, V, Object, W>(
          TypedMapColumn<V>.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: MapTransformer<V>(fromJson: fromJson),
          synthetic: synthetic,
        )
        as T;
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
