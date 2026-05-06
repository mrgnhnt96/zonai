import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

import 'src/load_migrations.dart';

export 'package:raindrop/raindrop.dart';
export 'package:raindrop_sqlite/raindrop_sqlite.dart';
export 'column_types/column_types.dart';
export 'schemas/ids.dart';
export 'schemas/items.dart';
export 'src/load_migrations.dart';

/// Opens (or creates) a SQLite file under [directory] and runs [migrations].
///
/// Default [directory] is `./data` relative to [fileSystem]'s current directory
/// (defaults to [LocalFileSystem]). The file is named [databaseFileName] inside
/// that directory (default `zonai.sqlite`).
///
/// SQL migrations are read from [migrationsDirectory], default `./migrations`
/// relative to the current directory (each `NNNN_name.sql` becomes a
/// [Migration] with that tag). Use a custom path when the process cwd is not
/// the package root.
Future<Raindrop> openZonaiDatabase({
  FileSystem? fileSystem,
  Directory? directory,
  String databaseFileName = 'zonai.sqlite',
  Directory? migrationsDirectory,
}) async {
  final fs = fileSystem ?? LocalFileSystem();
  final dir = directory ??
      fs.directory(fs.path.join(fs.currentDirectory.path, 'data'));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final migrationsDir = migrationsDirectory ??
      fs.directory(fs.path.join(fs.currentDirectory.path, 'migrations'));
  final migrations = await loadMigrationsFromDirectory(migrationsDir);

  final filePath = fs.path.join(dir.path, databaseFileName);
  final db = Raindrop(await ResqliteDelegate.open(filePath));
  await migrate(db, migrations);
  await db.ensureOpen();
  return db;
}
