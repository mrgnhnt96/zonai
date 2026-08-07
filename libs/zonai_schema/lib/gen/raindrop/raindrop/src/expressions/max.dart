// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `MAX(value)`, the largest value of [value] across the group.
Max<V> max<V>(ColumnOf<V> value) => Max<V>(value);

/// {@template max}
/// SQL `MAX(value)`.
/// {@endtemplate}
class Max<V> extends Expression<V> {
  /// {@macro max}
  Max(this.value);

  /// The column being aggregated.
  final ColumnOf<V> value;

  @override
  SQL build() => SQL.function('MAX', [value]);
}
