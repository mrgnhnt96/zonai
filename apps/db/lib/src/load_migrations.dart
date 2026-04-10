import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart';

/// Reads every `*.sql` file in [directory] (non-recursive), sorted by filename.
///
/// Each [Migration] tag is the basename without `.sql` (e.g. `0000_initial.sql`
/// → `0000_initial`), matching what `raindrop_cli generate` writes.
Future<List<Migration>> loadMigrationsFromDirectory(Directory directory) async {
  if (!directory.existsSync()) {
    throw StateError('Migrations directory does not exist: ${directory.path}');
  }

  final fs = directory.fileSystem;
  final sqlFiles = <File>[];
  for (final entity in directory.listSync()) {
    if (entity is! File) continue;
    if (!fs.path.extension(entity.path).toLowerCase().endsWith('.sql')) {
      continue;
    }
    sqlFiles.add(entity);
  }

  sqlFiles.sort(
    (a, b) => fs.path.basename(a.path).compareTo(fs.path.basename(b.path)),
  );

  final migrations = <Migration>[];
  for (final file in sqlFiles) {
    final name = fs.path.basenameWithoutExtension(file.path);
    final sql = (await file.readAsString()).trim();
    migrations.add(Migration(name, sql));
  }

  return migrations;
}
