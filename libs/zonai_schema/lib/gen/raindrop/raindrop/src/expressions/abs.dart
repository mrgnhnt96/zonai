// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `ABS(value)`, the absolute value of [value], keeping its type.
Abs<V> abs<V extends num?>(ColumnOr<V> value) => Abs<V>(value);

/// {@template abs}
/// SQL `ABS(value)`.
/// {@endtemplate}
class Abs<V extends num?> extends Expression<V> {
  /// {@macro abs}
  Abs(this.value);

  /// The number.
  final ColumnOr<V> value;

  @override
  SQL build() => SQL.function('ABS', [value]);
}
