// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `MIN(value)`, the smallest value of [value] across the group.
Min<V> min<V>(ColumnOf<V> value) => Min<V>(value);

/// {@template min}
/// SQL `MIN(value)`.
/// {@endtemplate}
class Min<V> extends Expression<V> {
  /// {@macro min}
  Min(this.value);

  /// The column being aggregated.
  final ColumnOf<V> value;

  @override
  SQL build() => SQL.function('MIN', [value]);
}
