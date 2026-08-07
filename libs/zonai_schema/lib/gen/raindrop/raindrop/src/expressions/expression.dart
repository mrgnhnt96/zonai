// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// {@template expression}
/// A typed SQL expression that produces a value of type [V].
/// {@endtemplate}
abstract class Expression<V> implements Selectable<V> {
  /// {@macro expression}
  const Expression();

  /// Build the underlying [SQL] for this expression.
  SQL build();
}
