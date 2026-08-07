// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

/// SQLite supports `LIMIT` on `UPDATE`.
extension SQLiteUpdateLimit<S extends Schema<R>, R, V>
    on UpdateWhereBuilder<S, R, V> {
  /// Cap how many rows the update affects.
  UpdateWhereBuilder<S, R, V> limit(int limit) =>
      withClause(UpdateSlot.where + 1000, LimitClause(limit));
}
