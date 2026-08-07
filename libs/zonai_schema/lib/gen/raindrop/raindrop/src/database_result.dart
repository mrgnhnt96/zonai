// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

/// {@template database_result}
/// The result from the database on any given query.
/// {@endtemplate}
class DatabaseResult {
  /// {@macro database_result}
  const DatabaseResult({
    required this.columns,
    required this.rows,
    required this.rowsAffected,
    required this.lastInsertedRowId,
  });

  /// The column names returned by the query.
  final List<String> columns;

  /// The rows returned by the database from the query.
  final List<List<Object?>> rows;

  /// The rows affected by the query.
  final int rowsAffected;

  /// The last inserted row id.
  final int? lastInsertedRowId;
}
