// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Floating-point numbers, stored as a REAL.
extension RealColumnDefinition<R> on SchemaBuilder<R> {
  /// A [double] column, stored as an 8-byte IEEE floating point number.
  ///
  /// [defaultValue] is what existing rows get when this column is added to a
  /// table that already has some -- without it, a non-nullable column cannot
  /// be added at all, because there is no value to backfill them with.
  ColumnType<W> real<W extends double?>(
    String name,
    Field<R, W> field, {
    ColumnOr<double>? defaultValue,
  }) {
    return column<double, W>(
      name,
      field,
      sqlType: 'REAL',
      defaultValue: defaultValue,
    );
  }
}
