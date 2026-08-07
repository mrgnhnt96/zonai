// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension BooleanColumnDefinition<R> on SchemaBuilder<R> {
  ColumnType<W> boolean<W extends bool?>(
    String name,
    Field<R, W> field, {
    String? defaultValue,
  }) {
    return custom<bool, int, W>(
      name,
      field,
      transformer: const BooleanTransfomer(),
      sqlType: 'INTEGER',
      defaultValue: defaultValue,
    );
  }
}

class BooleanTransfomer extends ColumnTransformer<bool, int> {
  const BooleanTransfomer();

  @override
  int encode(bool input) => input ? 1 : 0;

  @override
  bool decode(int input) => input == 1;
}
