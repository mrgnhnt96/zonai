// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/builders/limited_write.dart';

/// SQLite supports capping an `UPDATE`.
extension SQLiteUpdateLimit<S extends Schema<R>, R, V>
    on UpdateWhereBuilder<S, R, V> {
  /// Cap how many rows the update affects.
  UpdateLimitedBuilder<S, R, V> limit(int limit) => withClause(
        UpdateSlot.where,
        (config) => LimitedWriteClause(
          table: config.table!,
          filter: config.where,
          limit: limit,
        ),
        UpdateLimitedBuilder.new,
      ).withClause(
        // Past `RETURNING` at `where + 5000`: SQLite parses the bare
        // `LIMIT` only there.
        UpdateSlot.where + 10000,
        (config) => LimitedWriteTailClause(limit),
        UpdateLimitedBuilder.new,
      );
}
