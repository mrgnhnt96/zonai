import 'dart:convert';

import 'package:raindrop/raindrop.dart';

/// Column handle for a JSON string array stored in TEXT (SQLite json1).
///
/// On columns using [ListTransformer], `TableOperations.update` maps
/// add / remove update operations to JSON array append and remove-by-value
/// (not numeric `+` / `-`).
extension ListColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> list<E, W extends List<E>?>(
    String name,
    Field<S, W> field, {
    required E Function(dynamic) fromJson,
  }) {
    return custom<List<E>, Object, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: ListTransformer<E>(fromJson: fromJson),
    );
  }
}

class ListTransformer<T> extends ColumnTransformer<List<T>, Object> {
  const ListTransformer({required this.fromJson});

  final T Function(dynamic) fromJson;

  @override
  String encode(List<T> input) => jsonEncode(input);

  @override
  List<T> decode(Object input) {
    if (input is List<T>) {
      return input;
    }

    if (input is List) {
      return input.map(fromJson).toList();
    }

    if (input is String) {
      if (input.isEmpty) {
        return [];
      }

      return (jsonDecode(input) as List<dynamic>).map(fromJson).toList();
    }

    throw ArgumentError.value(
      input,
      'input',
      'Expected JSON text or List, got ${input.runtimeType}',
    );
  }
}
