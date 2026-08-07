// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension IntOperators<V extends int?> on ColumnOf<V> {
  /// Row value of column is greater than [value].
  SQL greaterThan(ColumnOr<int> value) => SQL([this, Op.greaterThan, value]);

  /// Row value of column is greater than or equal [value].
  SQL greaterThanOrEqual(ColumnOr<int> value) =>
      SQL([this, Op.greaterThanOrEqual, value]);

  /// Row value of column is greater than [value].
  SQL operator >(ColumnOr<int> value) => greaterThan(value);

  /// Row value of column is greater than or equal [value].
  SQL operator >=(ColumnOr<int> value) => greaterThanOrEqual(value);

  /// Row value of column is less than [value].
  SQL lessThan(ColumnOr<int> value) => SQL([this, Op.lessThan, value]);

  /// Row value of column is less than or equal [value].
  SQL lessThanOrEqual(ColumnOr<int> value) =>
      SQL([this, Op.lessThanOrEqual, value]);

  /// Row value of column is less than [value].
  SQL operator <(ColumnOr<int> value) => lessThan(value);

  /// Row value of column is less than or equal [value].
  SQL operator <=(ColumnOr<int> value) => lessThanOrEqual(value);
}
