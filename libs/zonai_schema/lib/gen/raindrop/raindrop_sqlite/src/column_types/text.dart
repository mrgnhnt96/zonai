// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Strings, stored as a TEXT.
extension TextColumnDefinition<R> on SchemaBuilder<R> {
  /// A [String] column, optionally with a [defaultValue].
  ColumnType<W> text<W extends String?>(
    String name,
    Field<R, W> field, {
    ColumnOr<String>? defaultValue,
  }) {
    return column<String, W>(
      name,
      field,
      sqlType: 'TEXT',
      defaultValue: defaultValue,
    );
  }
}
