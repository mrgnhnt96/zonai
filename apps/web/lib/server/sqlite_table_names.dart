import 'package:scoped_deps/scoped_deps.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/deps.dart' as deps;
import 'package:zonai/zonai.dart';
import 'package:zonai_web/utils/sqlite_table_utils.dart';

typedef SqliteTablesPayload = ({List<String> sqliteNames, List<String> displayNames, String? error});

/// Label shown in the UI (e.g. Raindrop's migrations table uses a shorter name).
String sqliteTableDisplayName(String rawName) => rawName == '_raindrop_migrations' ? '_migrations' : rawName;

/// Alphabetized with non-`_` tables first; `_`-prefixed tables last (also alphabetized by label).
List<({String raw, String label})> orderSqliteTablesForDisplay(Iterable<String> rawNames) {
  final rows = [for (final raw in rawNames) (raw: raw, label: sqliteTableDisplayName(raw))]
    ..sort((a, b) {
      final aInternal = isSystemSqliteTable(a.raw);
      final bInternal = isSystemSqliteTable(b.raw);
      if (aInternal != bInternal) {
        return aInternal ? 1 : -1;
      }
      return a.label.compareTo(b.label);
    });
  return [for (final r in rows) (raw: r.raw, label: r.label)];
}

SqliteTablesPayload loadZonaiSqliteTableNames() {
  return runScoped(() {
    try {
      final settings = kIsCompiled ? deps.settings : Settings.load(fs.path.join('..', 'playground'));
      final dbFile = fs.file(settings.zonaiSqlitePath);
      if (!dbFile.existsSync()) {
        return (sqliteNames: <String>[], displayNames: <String>[], error: null);
      }
      final db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
      try {
        final rows = db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        );
        final raw = [for (final row in rows) row['name'] as String];
        final ordered = orderSqliteTablesForDisplay(raw);
        return (
          sqliteNames: [for (final o in ordered) o.raw],
          displayNames: [for (final o in ordered) o.label],
          error: null,
        );
      } finally {
        db.dispose();
      }
    } catch (e) {
      return (sqliteNames: <String>[], displayNames: <String>[], error: '$e');
    }
  }, values: {fsProvider, argsProvider.overrideWith(() => const Args())});
}
