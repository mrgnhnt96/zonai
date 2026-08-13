// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Predicates for boolean columns.
extension BoolOperators<V extends bool?> on ColumnOf<V> {
  /// Row value of column is true.
  SQL isTrue() => equals(true as V);

  /// Row value of column is false.
  SQL isFalse() => equals(false as V);
}
