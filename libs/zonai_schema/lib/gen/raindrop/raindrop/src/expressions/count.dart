// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `COUNT(...)`.
///
/// `count()` produces `COUNT(*)` while `count(column)` produces `COUNT(column)`
/// The result is always an `int`, the counted column's type is irrelevant, so
/// this isn't generic (which also lets `count()` be called with no arguments).
///
/// Wrap the operand in `distinct()` to count each value once.
Count<Object?> count([Selectable<Object?>? value]) => Count<Object?>(value);

/// {@template count}
/// SQL `COUNT(value)`, or `COUNT(*)` when [value] is null.
/// {@endtemplate}
class Count<V> extends Expression<int> {
  /// {@macro count}
  const Count([this.value]);

  /// What is being counted, or null for `COUNT(*)`.
  final Selectable<V>? value;

  @override
  SQL build() => switch (value) {
        null => SQL([const RawSQL('COUNT(*)')]),
        final value => SQL.function('COUNT', [value]),
      };
}
