// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

/// Result of running a dialect DDL generator over diff operations.
class DdlGenerateResult {
  /// Creates a DDL generation result with optional [warnings].
  const DdlGenerateResult({
    required this.sql,
    this.warnings = const [],
  });

  /// Generated SQL (possibly empty).
  final String sql;

  /// Non-fatal messages from the generator (e.g. inferred defaults).
  final List<String> warnings;
}
