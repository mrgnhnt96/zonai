import 'dart:convert';

import 'package:raindrop/raindrop.dart';

/// Column handle for a JSON object stored in TEXT (SQLite json1).
///
/// On columns using [ObjectMapTransformer], [CollectionOperations.update]
/// supports dotted [ColumnUpdate] paths (e.g. `profile.displayName`) via
/// `json_set`, and shallow [ObjectUpdate] maps merge via `json_patch` instead
/// of replacing the whole value.
extension type MapColumn(Map<String, dynamic> _)
    implements ColumnType<Map<String, dynamic>>, Map<String, dynamic> {}

extension MapColumnDefinition<S> on SchemaBuilder<S> {
  /// JSON object column; values are stored as JSON text.
  MapColumn map(String name, Field<S, Map<String, dynamic>> field) {
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
          transformer: const ObjectMapTransformer(),
          synthetic: const {},
        )
        as MapColumn;
  }
}

class ObjectMapTransformer
    extends ColumnTransformer<Map<String, dynamic>, Object> {
  const ObjectMapTransformer();

  @override
  String encode(Map<String, dynamic> input) => jsonEncode(input);

  @override
  Map<String, dynamic> decode(Object input) {
    if (input is Map<String, dynamic>) {
      return Map<String, dynamic>.from(input);
    }

    if (input is Map) {
      return Map<String, dynamic>.from(input.map((k, v) => MapEntry('$k', v)));
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
      return Map<String, dynamic>.from(decoded);
    }

    throw ArgumentError.value(
      input,
      'input',
      'Expected JSON text or Map, got ${input.runtimeType}',
    );
  }
}
