import 'client_settings.dart';

/// A table name that cannot be turned into Dart names.
///
/// Loud on purpose. The alternative -- mangling `2fa_tokens` into something
/// that happens to compile -- produces a class name nobody asked for and no
/// message saying where it came from.
final class ClientNameException implements Exception {
  const ClientNameException({
    required this.table,
    required this.derived,
    required this.reason,
  });

  final String table;

  /// What the naming scheme produced, so the message can show its work.
  final String derived;

  final String reason;

  String get message =>
      'Cannot generate a client for table `$table`: $reason (got `$derived`).\n'
      '\n'
      'Set a name for it in zonai.yaml:\n'
      '\n'
      'client:\n'
      '  names:\n'
      '    $table:\n'
      '      row: SomethingRow';

  @override
  String toString() => message;
}

/// The Dart names one table gets.
///
/// Every name is derived from a single [base] so they cannot drift apart:
/// `Posts` yields `PostsRow`, `PostsId`, `PostsExpanded`, `PostsApi` and the
/// `posts` getter on `ZonaiTables`.
///
/// `names.<table>.row` overrides [base] rather than only the row class. A
/// table whose *name* is the problem -- a reserved word, a leading digit --
/// is unfixable if the override reaches one class out of four, and that
/// override is the only escape hatch the config has.
final class TableNames {
  const TableNames({required this.table, required this.base});

  final String table;

  /// PascalCase stem shared by every generated name for this table.
  final String base;

  /// §10.1: no singularization. `posts` → `Posts`, never `Post`.
  ///
  /// `names.<table>.row` wins, with a trailing `Row` stripped so an override
  /// of `BlogPostsRow` still yields `BlogPostsId` rather than `BlogPostsRowId`.
  factory TableNames.forTable(String table, ClientSettings settings) {
    final override = settings.rowNameFor(table);
    final base = override == null ? _pascal(table) : _stripRowSuffix(override);

    if (!_identifier.hasMatch(base)) {
      throw ClientNameException(
        table: table,
        derived: base,
        reason:
            'the generated class name is not a Dart identifier -- it must '
            'start with a letter and contain only letters, digits and '
            'underscores',
      );
    }

    final names = TableNames(table: table, base: base);
    if (_reservedWords.contains(names.getter)) {
      throw ClientNameException(
        table: table,
        derived: names.getter,
        reason:
            'the accessor `client.${names.getter}` would be the Dart '
            'reserved word `${names.getter}`',
      );
    }

    return names;
  }

  /// Read model. `PostsRow`.
  String get row => '${base}Row';

  /// Id type. `PostsId`.
  String get id => '${base}Id';

  /// Expanded-relations holder. `PostsExpanded`.
  String get expanded => '${base}Expanded';

  /// Per-table API. `PostsApi`.
  String get api => '${base}Api';

  /// The live-query mirror: `posts` -> `PostsListen`.
  String get listen => '${base}Listen';

  /// The create builder: `posts` -> `PostsCreate`.
  String get create => '${base}Create';

  /// The update builder: `posts` -> `PostsUpdate`.
  String get update => '${base}Update';

  /// The typed `expand` path builder: `posts` -> `PostsExpand`.
  ///
  /// Distinct from [expanded] (`PostsExpanded`), which is the *response* side.
  /// One asks for related rows, the other holds them.
  String get expand => '${base}Expand';

  /// The column-token holder: `posts` -> `Posts`.
  ///
  /// Deliberately the bare base name. Nothing tries to guess an English
  /// singular (§10), and `Posts` cannot collide with `PostsRow` / `PostsId` /
  /// `PostsApi`, which are all suffixed.
  String get tokens => base;

  /// The `ZonaiTables` accessor. `client.posts`.
  String get getter => base[0].toLowerCase() + base.substring(1);

  /// Path relative to the output directory.
  ///
  /// Under `tables/` so no table can collide with the barrel or the shared
  /// runtime, whatever it is called.
  String get file => 'tables/$baseFileName';

  /// File name alone, for a sibling table importing this one.
  String get baseFileName => '$table.g.dart';

  static final _identifier = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

  static String _pascal(String raw) => raw
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();

  static String _stripRowSuffix(String name) =>
      name.length > 3 && name.endsWith('Row')
      ? name.substring(0, name.length - 3)
      : name;
}

/// Two tables that resolved to the same Dart names in one generation run.
///
/// §10.4 leaves this to the developer, so it is a warning and not a refusal --
/// but it is a warning that names both tables, because "duplicate class
/// `PostsRow`" from the analyzer names neither.
final class TableNameCollision {
  const TableNameCollision({required this.base, required this.tables});

  final String base;
  final List<String> tables;

  String get message =>
      'Tables ${tables.map((t) => '`$t`').join(' and ')} both generate '
      '`${base}Row` / `${base}Id` / `${base}Api`, which will not compile.\n'
      'Give one of them a different name in zonai.yaml:\n'
      '\n'
      'client:\n'
      '  names:\n'
      '    ${tables.first}:\n'
      '      row: SomethingElseRow\n'
      '\n'
      'This check only sees one generation run. Two *projects* each minting a '
      '`UsersId` collide at the import site instead, and that is resolved '
      'there with an import prefix.';
}

/// Names for every table in one run, plus whatever collided.
final class ClientNameTable {
  const ClientNameTable({required this.byTable, required this.collisions});

  final Map<String, TableNames> byTable;
  final List<TableNameCollision> collisions;

  factory ClientNameTable.forTables(
    Iterable<String> tables,
    ClientSettings settings,
  ) {
    final byTable = {
      for (final table in tables) table: TableNames.forTable(table, settings),
    };

    final byBase = <String, List<String>>{};
    for (final entry in byTable.entries) {
      (byBase[entry.value.base] ??= []).add(entry.key);
    }

    return ClientNameTable(
      byTable: byTable,
      collisions: [
        for (final entry in byBase.entries)
          if (entry.value.length > 1)
            TableNameCollision(base: entry.key, tables: entry.value),
      ],
    );
  }

  TableNames? operator [](String table) => byTable[table];
}

/// Words that cannot be a Dart identifier at all.
///
/// Built-in identifiers (`as`, `factory`, `get`, ...) are deliberately absent:
/// they are legal member and parameter names, which is why §5.8's
/// `Authorization? as` works.
const _reservedWords = {
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
};
