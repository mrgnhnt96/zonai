// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

/// Appends `LIMIT` on `DELETE`.
///
/// Only works when SQLite was built from source with lemon regenerated under
/// `SQLITE_ENABLE_UPDATE_DELETE_LIMIT`. The sqlite3mc amalgamation (resqlite)
/// does not support this — prefer rewriting as
/// `DELETE … WHERE pk IN (SELECT pk … LIMIT n)` at the call site.
extension SQLiteDeleteLimit<S extends Schema<R>, R, V>
    on DeleteWhereBuilder<S, R, V> {
  /// Cap how many rows the delete affects.
  DeleteWhereBuilder<S, R, V> limit(int limit) =>
      withClause(DeleteSlot.where + 1000, LimitClause(limit));
}
