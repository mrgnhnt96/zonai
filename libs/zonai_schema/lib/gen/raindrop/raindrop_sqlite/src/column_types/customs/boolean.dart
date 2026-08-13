// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Booleans, stored as an INTEGER.
extension BooleanColumnDefinition<R> on SchemaBuilder<R> {
  /// A [bool] column: `true` is stored as `1` and `false` as `0`.
  ColumnType<W> boolean<W extends bool?>(
    String name,
    Field<R, W> field, {
    ColumnOr<bool>? defaultValue,
  }) {
    return custom<bool, int, W>(
      name,
      field,
      transformer: const BooleanTransformer(),
      sqlType: 'INTEGER',
      defaultValue: defaultValue,
    );
  }
}

/// {@template boolean_transformer}
/// Encodes a [bool] as an [int], where `true` becomes `1` and `false`
/// becomes `0`.
/// {@endtemplate}
class BooleanTransformer extends ColumnTransformer<bool, int> {
  /// {@macro boolean_transformer}
  const BooleanTransformer();

  @override
  int encode(bool input) => input ? 1 : 0;

  @override
  bool decode(int input) => input == 1;
}
