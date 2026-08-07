// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

/// SQLite-specific [Query] metadata (SQLite 3.35+).
mixin SQLiteLimitedQuery {
  /// When non-null, adds `LIMIT` after `WHERE` (and before `RETURNING`).
  int? get limit;
}
