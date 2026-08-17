/// The `client:` block in `zonai.yaml` — everything `zonai gen client` needs
/// to know, so the command itself takes no required arguments.
///
/// The server project cannot be an app dependency (`zonai_schema` pulls native
/// SQLite), so the generator writes into a directory the *app* owns. That
/// makes [output] the one genuinely required key: without it there is nowhere
/// to write and the command has nothing to do.
library;

/// Per-table overrides of the default naming scheme.
///
/// `posts` → `PostsRow` by default; `names.posts.row` replaces that one name
/// without changing the scheme for any other table.
final class ClientNameOverrides {
  const ClientNameOverrides({this.row});

  /// Overrides the generated read-model class name for this table.
  ///
  /// It moves more than the row class. Every generated name is derived from
  /// one stem, so `row: BlogPostsRow` also yields `BlogPostsId`,
  /// `BlogPostsApi` and `client.blogPosts`. An override reaching one name out
  /// of four would be no escape hatch at all for the case that most needs
  /// one -- a table name that is not a usable Dart identifier.
  final String? row;

  factory ClientNameOverrides.fromJson(Map<String, dynamic> json) {
    return ClientNameOverrides(
      row: switch (json['row']) {
        null => null,
        final String value => value,
        final value => throw FormatException(
          'Invalid client.names.<table>.row: $value. Expected a class name.',
        ),
      },
    );
  }

  Map<String, dynamic> toJson() => {if (row != null) 'row': row};

  @override
  bool operator ==(Object other) =>
      other is ClientNameOverrides && row == other.row;

  @override
  int get hashCode => row.hashCode;
}

/// Parsed `client:` block. Absent from `zonai.yaml` ⇒ `Settings.client` is
/// `null`, which is what `zonai gen client` reports on.
final class ClientSettings {
  const ClientSettings({
    this.output,
    this.package = false,
    this.packageName,
    this.excludeTables = const [],
    this.includeTables = const [],
    this.names = const {},
  });

  /// Where to write the generated client, normalized against the project root.
  ///
  /// Nullable rather than required because a `client:` block that forgot it is
  /// a *command* error with a fixable message, not a reason for `zonai serve`
  /// to refuse to start.
  final String? output;

  /// Emit a `pubspec.yaml` alongside the generated sources.
  final bool package;

  /// Name for that pubspec. Only read when [package] is true.
  final String? packageName;

  /// Tables to leave out. Default: every registered table.
  final List<String> excludeTables;

  /// Framework-internal tables to generate anyway.
  ///
  /// The escape hatch for [isInternalTable]'s default. Nothing else can bring
  /// a `_`-prefixed table back, and it has to be nameable: a project genuinely
  /// reading `_log` should not have to fork the generator.
  final List<String> includeTables;

  /// Per-table name overrides, keyed by table name.
  final Map<String, ClientNameOverrides> names;

  /// Parses the `client:` value from an already-JSON-ified `zonai.yaml`.
  ///
  /// [normalize] is the caller's path normalizer, so `output` resolves the
  /// same way `schemasPath` and friends already do.
  factory ClientSettings.fromJson(
    Map<String, dynamic> json, {
    required String Function(List<String>) normalize,
  }) {
    return ClientSettings(
      output: switch (json['output']) {
        null => null,
        final String value => normalize([value]),
        final value => throw FormatException(
          'Invalid client.output: $value. Expected a directory path.',
        ),
      },
      package: switch (json['package']) {
        null => false,
        final bool value => value,
        final value => throw FormatException(
          'Invalid client.package: $value. Expected true or false.',
        ),
      },
      packageName: switch (json['packageName']) {
        null => null,
        final String value => value,
        final value => throw FormatException(
          'Invalid client.packageName: $value. Expected a package name.',
        ),
      },
      excludeTables: switch (json['tables']) {
        null => const [],
        final Map<String, dynamic> tables => switch (tables['exclude']) {
          null => const [],
          final List<dynamic> value => [
            for (final entry in value)
              if (entry case final String table)
                table
              else
                throw FormatException(
                  'Invalid client.tables.exclude entry: $entry. Expected a '
                  'table name.',
                ),
          ],
          final value => throw FormatException(
            'Invalid client.tables.exclude: $value. Expected a list of table '
            'names.',
          ),
        },
        final value => throw FormatException(
          'Invalid client.tables: $value. Expected a map with an `exclude` '
          'list.',
        ),
      },
      includeTables: switch (json['tables']) {
        null => const [],
        final Map<String, dynamic> tables => switch (tables['include']) {
          null => const [],
          final List<dynamic> value => [
            for (final entry in value)
              if (entry case final String table)
                table
              else
                throw FormatException(
                  'Invalid client.tables.include entry: $entry. Expected a '
                  'table name.',
                ),
          ],
          final value => throw FormatException(
            'Invalid client.tables.include: $value. Expected a list of table '
            'names.',
          ),
        },
        final value => throw FormatException(
          'Invalid client.tables: $value. Expected a map with an `exclude` '
          'list.',
        ),
      },
      names: switch (json['names']) {
        null => const {},
        final Map<String, dynamic> value => {
          for (final entry in value.entries)
            entry.key: switch (entry.value) {
              final Map<String, dynamic> overrides =>
                ClientNameOverrides.fromJson(overrides),
              final other => throw FormatException(
                'Invalid client.names.${entry.key}: $other. Expected a map of '
                'name overrides (e.g. `row: BlogPostsRow`).',
              ),
            },
        },
        final value => throw FormatException(
          'Invalid client.names: $value. Expected a map keyed by table name.',
        ),
      },
    );
  }

  /// True when this block names somewhere to write.
  bool get hasOutput => output != null;

  /// The `row` override for [table], or null to use the default scheme.
  String? rowNameFor(String table) => names[table]?.row;

  /// Whether [table] should appear in the generated client.
  ///
  /// Two rules, in order: `client.tables.exclude` always wins, and a
  /// framework-internal table needs `client.tables.include` to opt back in.
  bool includesTable(String table) {
    if (excludeTables.contains(table)) return false;
    if (isInternalTable(table)) return includeTables.contains(table);
    return true;
  }

  /// Whether [table] is one zonai owns rather than one the project declared.
  ///
  /// The `_` prefix is this repo's established convention for system tables --
  /// `zonai rules` sorts on exactly this test and calls them system tables,
  /// and `_photos` / `_push_jobs` are described in the db mutator as internal
  /// tables whose schema zonai owns statically.
  ///
  /// This matters more for a *typed* client than for anything else that reads
  /// them. A generated `JwtApi` / `LogApi` / `RateLimitApi` is discoverable and
  /// autocompleting, which — given that types say nothing about permission —
  /// makes it read as a supported API over tables a consumer must never touch.
  /// So they are skipped by default, loudly (the command reports what it
  /// skipped) and reversibly ([includeTables]).
  static bool isInternalTable(String table) => table.startsWith('_');

  /// The tables of [all] this configuration leaves out, sorted.
  List<String> excludedFrom(Iterable<String> all) => [
    for (final table in all)
      if (!includesTable(table)) table,
  ]..sort();
}
