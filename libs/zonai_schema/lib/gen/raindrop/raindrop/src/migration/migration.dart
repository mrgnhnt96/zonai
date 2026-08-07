// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

/// {@template migration}
/// A single migration unit containing a tag and SQL content.
/// {@endtemplate}
class Migration {
  /// {@macro migration}
  const Migration(this.tag, this.sql);

  /// The migration identifier, e.g. "0000_initial".
  final String tag;

  /// The full SQL content to execute.
  final String sql;
}
