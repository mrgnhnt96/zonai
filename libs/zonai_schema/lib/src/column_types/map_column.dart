import 'dart:convert';

import 'package:raindrop/raindrop.dart';

/// JSON object as [Map<String, dynamic>], stored in TEXT
extension type MapColumn(Map<String, dynamic> _)
    implements ColumnType<Map<String, dynamic>>, Map<String, dynamic> {}

/// JSON object as [T], stored in TEXT
extension type TypedMapColumn<T>(T _) implements ColumnType<T> {}

extension MapColumnDefinition<S> on SchemaBuilder<S> {
  /// JSON object as [Map<String, dynamic>], stored in TEXT
  MapColumn map(
    String name,
    Field<S, Map<String, dynamic>> field, {
    Map<String, dynamic> Function(dynamic) fromJson = _mapFromDynamic,
  }) {
    return custom<
          MapColumn,
          Map<String, dynamic>,
          Object,
          Map<String, dynamic>
        >(
          MapColumn.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: MapTransformer<Map<String, dynamic>>(fromJson: fromJson),
          synthetic: {},
        )
        as MapColumn;
  }

  static Map<String, dynamic> _mapFromDynamic(dynamic d) =>
      Map<String, dynamic>.from(d as Map);

  /// JSON object as [T], stored in TEXT
  TypedMapColumn<T> mapAs<T extends Object>(
    String name,
    Field<S, T> field, {
    required T Function(dynamic) fromJson,
    required T synthetic,
  }) {
    return custom<TypedMapColumn<T>, T, Object, T>(
          TypedMapColumn<T>.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: MapTransformer<T>(fromJson: fromJson),
          synthetic: synthetic,
        )
        as TypedMapColumn<T>;
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
