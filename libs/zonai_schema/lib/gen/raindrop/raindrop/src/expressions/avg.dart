// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `AVG(value)`, the mean of [value] across the group.
Avg avg(ColumnOr<num?> value) => Avg(value);

/// {@template avg}
/// SQL `AVG(value)`.
///
/// Always produces a floating point number, whatever went in, averaging
/// integers gives a fraction.
/// {@endtemplate}
class Avg extends Expression<double> {
  /// {@macro avg}
  Avg(this.value);

  /// The column or expression being averaged.
  final ColumnOr<num?> value;

  @override
  SQL build() => SQL.function('AVG', [value]);

  @override
  double? decode(Object? input) => switch (input) {
        null => null,
        final num number => number.toDouble(),
        final String text => double.parse(text),
        _ => input as double?,
      };
}
