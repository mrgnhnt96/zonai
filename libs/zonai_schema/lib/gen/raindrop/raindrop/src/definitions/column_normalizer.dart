// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

/// A rule a text column's values always obey, declared on the column so that
/// raindrop can keep to it everywhere a value passes through.
///
/// ```dart
/// email = $.column('email', (row) => row.email).lowercase(),
/// ```
///
/// Declaring one does three things:
///
/// - every value raindrop writes or compares against the column is
///   normalized first, so `where(users.email.equals('Ann@Example.com'))`
///   finds `ann@example.com`;
/// - the table gains a CHECK constraint holding the database to the same rule;
/// - `generate` sees the declaration change, and when it is added to a column
///   that already has rows, writes the UPDATE that brings those rows into line
///   ahead of the constraint that would otherwise reject them.
///
/// That last one is why this is a declaration and not a one-off data
/// migration: the generator diffs what the schema declares, so a rule it can
/// see is a rule it can migrate.
enum ColumnNormalizer {
  /// Folded to lower case, `LOWER(value)`.
  lowercase('LOWER');

  const ColumnNormalizer(this.sqlFunction);

  /// The SQL function that applies this rule, understood by every dialect
  /// raindrop supports.
  final String sqlFunction;

  /// The normalizer named [name], as a snapshot records it.
  ///
  /// Throws an [ArgumentError] for a name this version does not know, rather
  /// than dropping a rule a newer schema declared.
  static ColumnNormalizer byName(String name) {
    for (final normalizer in values) {
      if (normalizer.name == name) return normalizer;
    }
    throw ArgumentError.value(name, 'name', 'unknown column normalizer');
  }

  /// [value] normalized in Dart, as the database would normalize it.
  String apply(String value) => switch (this) {
        lowercase => value.toLowerCase(),
      };
}
