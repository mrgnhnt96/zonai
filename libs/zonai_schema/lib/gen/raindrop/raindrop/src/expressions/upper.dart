// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `UPPER(value)`, [value] folded to upper case.
Upper upper(ColumnOr<String?> value) => Upper(value);

/// {@template upper}
/// SQL `UPPER(value)`.
/// {@endtemplate}
class Upper extends Expression<String> {
  /// {@macro upper}
  Upper(this.value);

  /// What is being folded.
  final ColumnOr<String?> value;

  @override
  SQL build() => SQL.function('UPPER', [value]);
}
