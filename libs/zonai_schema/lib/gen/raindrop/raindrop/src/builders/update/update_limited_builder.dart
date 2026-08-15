// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

/// {@template update_limited_builder}
/// An update whose row cap is set: still awaitable and decoratable, no
/// longer filterable.
/// {@endtemplate}
class UpdateLimitedBuilder<S extends Schema<R>, R, V>
    extends UpdateBuilder<S, R, V> with ToQuery<S, V> {
  /// {@macro update_limited_builder}
  UpdateLimitedBuilder(super.executor, {required super.config});

  @override
  Query<V> compile({bool qualified = false}) => Query<V>(
        shape: config.table!,
        clauses: {
          UpdateSlot.verb: const Keyword('UPDATE'),
          UpdateSlot.table: TableClause(config.table!),
          UpdateSlot.set: SetClause(config.set!),
          if (config.where case final where?)
            UpdateSlot.where: WhereClause(where, singleTable: true),
          ...config.buildExtras(),
        },
      );
}
