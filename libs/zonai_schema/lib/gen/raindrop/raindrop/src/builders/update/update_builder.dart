// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// {@template update_builder}
/// Base update builder class.
/// {@endtemplate}
abstract class UpdateBuilder<S extends Schema<R>, R, V>
    extends QueryBuilder<S, V> {
  /// {@macro update_builder}
  UpdateBuilder(super.executor, {required super.config});
}
