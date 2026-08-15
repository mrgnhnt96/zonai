// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/builders/limited_write.dart';

/// SQLite supports capping a `DELETE`.
extension SQLiteDeleteLimit<S extends Schema<R>, R, V>
    on DeleteWhereBuilder<S, R, V> {
  /// Cap how many rows the delete affects.
  DeleteLimitedBuilder<S, R, V> limit(int limit) => withClause(
        DeleteSlot.where,
        (config) => LimitedWriteClause(
          table: config.from!,
          filter: config.where,
          limit: limit,
        ),
        DeleteLimitedBuilder.new,
      ).withClause(
        // Past `RETURNING` at `where + 5000`: SQLite parses the bare
        // `LIMIT` only there.
        DeleteSlot.where + 10000,
        (config) => LimitedWriteTailClause(limit),
        DeleteLimitedBuilder.new,
      );
}
