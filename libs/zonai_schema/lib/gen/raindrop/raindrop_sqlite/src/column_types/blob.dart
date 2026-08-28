// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:typed_data';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Raw binary data, stored as a BLOB.
extension BlobColumnDefinition<R> on SchemaBuilder<R> {
  /// A [Uint8List] column, stored as-is in a BLOB.
  ///
  /// [defaultValue] is what existing rows get when this column is added to a
  /// table that already has some -- without it, a non-nullable column cannot
  /// be added at all, because there is no value to backfill them with.
  ColumnType<W> blob<W extends Uint8List?>(
    String name,
    Field<R, W> field, {
    ColumnOr<Uint8List>? defaultValue,
  }) {
    return column<Uint8List, W>(
      name,
      field,
      sqlType: 'BLOB',
      defaultValue: defaultValue,
    );
  }
}
