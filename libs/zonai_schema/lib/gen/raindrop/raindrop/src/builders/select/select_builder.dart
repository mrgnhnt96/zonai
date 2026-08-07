// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Phantom type used as the schema slot in [SelectBuilder] before a
/// concrete schema has been selected via `.from`.
class NoSchema {
  const NoSchema._();
}

/// {@template select_builder}
/// Select builder for select queries
/// {@endtemplate}
class SelectBuilder<V extends Object?> extends QueryBuilder<NoSchema, V> {
  /// {@macro select_builder}
  SelectBuilder(
    super.executor, {
    required super.config,
  });
}
