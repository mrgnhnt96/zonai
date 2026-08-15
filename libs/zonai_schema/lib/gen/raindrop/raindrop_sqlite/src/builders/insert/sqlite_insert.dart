// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

/// Adds `insertOrIgnore` for SQLite, which skips rows that would violate a
/// constraint instead of failing.
extension SQLiteInsertOrIgnore on RaindropExecutor<Delegate> {
  /// Like `insert`, but skips rows that would violate a constraint instead of
  /// failing.
  InsertValuesBuilder<Schema<R>, R, void> insertOrIgnore<R>({
    required Schema<R> into,
  }) =>
      insert<R>(into: into).withClause(
        InsertSlot.verb + 500,
        (_) => const Keyword('OR IGNORE'),
        InsertValuesBuilder.new,
      );
}
