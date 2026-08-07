// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

export 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

export 'package:zonai_schema/gen/raindrop/raindrop/src/rendering/clause.dart';
export 'package:zonai_schema/gen/raindrop/raindrop/src/rendering/clauses.dart';
export 'package:zonai_schema/gen/raindrop/raindrop/src/rendering/render_context.dart';
export 'package:zonai_schema/gen/raindrop/raindrop/src/sql_dialect.dart';

/// Adds [withClause] to a select builder.
extension SelectFromWithClause<S extends Schema<R>, R, V>
    on SelectFromBuilder<S, R, V> {
  /// Returns a copy of this builder with [clause] placed at [weight].
  SelectFromBuilder<S, R, V> withClause(int weight, Clause clause) =>
      SelectFromBuilder(executor, config: config.addClause(weight, clause));
}

/// Adds [withClause] to a pre-`values` insert builder (to seed a verb
/// modifier like `OR IGNORE` before the rows are supplied).
extension InsertValuesWithClause<S extends Schema<R>, R, V>
    on InsertValuesBuilder<S, R, V> {
  /// Returns a copy of this builder with [clause] placed at [weight].
  InsertValuesBuilder<S, R, V> withClause(int weight, Clause clause) =>
      InsertValuesBuilder(executor, config: config.addClause(weight, clause));
}

/// Adds [withClause] to an insert builder.
extension InsertWithValuesWithClause<S extends Schema<R>, R, V>
    on InsertWithValuesBuilder<S, R, V> {
  /// Returns a copy of this builder with [clause] placed at [weight].
  InsertWithValuesBuilder<S, R, V> withClause(int weight, Clause clause) =>
      InsertWithValuesBuilder(
        executor,
        config: config.addClause(weight, clause),
      );
}

/// Adds [withClause] to an update builder.
extension UpdateWhereWithClause<S extends Schema<R>, R, V>
    on UpdateWhereBuilder<S, R, V> {
  /// Returns a copy of this builder with [clause] placed at [weight].
  UpdateWhereBuilder<S, R, V> withClause(int weight, Clause clause) =>
      UpdateWhereBuilder(executor, config: config.addClause(weight, clause));
}

/// Adds [withClause] to a delete builder.
extension DeleteWhereWithClause<S extends Schema<R>, R, V>
    on DeleteWhereBuilder<S, R, V> {
  /// Returns a copy of this builder with [clause] placed at [weight].
  DeleteWhereBuilder<S, R, V> withClause(int weight, Clause clause) =>
      DeleteWhereBuilder(executor, config: config.addClause(weight, clause));
}
