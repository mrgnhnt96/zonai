// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `TRIM(value)`, [value] with surrounding whitespace removed.
Trim trim(ColumnOr<String?> value) => Trim(value);

/// {@template trim}
/// SQL `TRIM(value)`.
/// {@endtemplate}
class Trim extends Expression<String> {
  /// {@macro trim}
  Trim(this.value);

  /// What is being trimmed.
  final ColumnOr<String?> value;

  @override
  SQL build() => SQL.function('TRIM', [value]);
}
