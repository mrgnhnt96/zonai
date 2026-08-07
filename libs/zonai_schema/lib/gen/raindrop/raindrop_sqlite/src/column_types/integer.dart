// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension IntColumnDefinition<R> on SchemaBuilder<R> {
  ColumnType<W> integer<W extends int?>(
    String name,
    Field<R, W> field, {
    String? defaultValue,
  }) {
    return column<int, W>(
      name,
      field,
      sqlType: 'INTEGER',
      defaultValue: defaultValue,
    );
  }
}
