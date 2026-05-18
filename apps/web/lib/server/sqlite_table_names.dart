import 'package:scoped_deps/scoped_deps.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';

typedef SqliteTablesPayload = ({List<String> names, String? error});

SqliteTablesPayload loadZonaiSqliteTableNames() {
  return runScoped(() {
    try {
      final settings = kIsCompiled ? Settings.load() : Settings.load(fs.path.join('..', 'playground'));
      final dbFile = fs.file(settings.zonaiSqlitePath);
      if (!dbFile.existsSync()) {
        return (names: <String>[], error: null);
      }
      final db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
      try {
        final rows = db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        );
        return (names: [for (final row in rows) row['name'] as String], error: null);
      } finally {
        db.dispose();
      }
    } catch (e) {
      return (names: <String>[], error: '$e');
    }
  }, values: {fsProvider, argsProvider.overrideWith(() => const Args())});
}
