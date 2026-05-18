import 'dart:convert';

import 'package:raindrop/raindrop.dart';

/// Column handle for a JSON string array stored in TEXT (SQLite json1).
///
/// On columns using [ListTransformer], `CollectionOperations.update` maps
/// add / remove update operations to JSON array append and remove-by-value
/// (not numeric `+` / `-`).
extension type ListColumn<T>(List<T> _)
    implements ColumnType<List<T>>, List<T> {}

extension ListColumnDefinition<S> on SchemaBuilder<S> {
  ListColumn<T> list<T>(
    String name,
    Field<S, List<T>> field, {
    required T Function(dynamic) fromJson,
  }) {
    return custom<ListColumn<T>, List<T>, Object, List<T>>(
          ListColumn<T>.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: ListTransformer<T>(fromJson: fromJson),
          synthetic: [],
        )
        as ListColumn<T>;
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
