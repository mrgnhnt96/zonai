// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// SQL `LOWER(value)`, [value] folded to lower case.
Lower lower(ColumnOr<String?> value) => Lower(value);

/// {@template lower}
/// SQL `LOWER(value)`.
/// {@endtemplate}
class Lower extends Expression<String> {
  /// {@macro lower}
  Lower(this.value);

  /// What is being folded.
  final ColumnOr<String?> value;

  @override
  SQL build() => SQL.function('LOWER', [value]);
}
