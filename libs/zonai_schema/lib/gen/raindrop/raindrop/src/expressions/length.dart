// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `LENGTH(value)`, the character count of [value].
Length length(ColumnOr<String?> value) => Length(value);

/// {@template length}
/// SQL `LENGTH(value)`.
/// {@endtemplate}
class Length extends Expression<int> {
  /// {@macro length}
  Length(this.value);

  /// What is being measured.
  final ColumnOr<String?> value;

  @override
  SQL build() => SQL.function('LENGTH', [value]);
}
