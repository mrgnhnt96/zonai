// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:typed_data';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension BlobColumnDefinition<R> on SchemaBuilder<R> {
  ColumnType<W> blob<W extends Uint8List?>(String name, Field<R, W> field) {
    return column<Uint8List, W>(name, field, sqlType: 'BLOB');
  }
}
