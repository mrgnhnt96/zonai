import 'package:raindrop/raindrop.dart' hide Table, table;
import 'package:zonai_schema/zonai_schema.dart';

/// Row shape for Raindrop's migration tracking table (created by [migrate]).
class RaindropMigrationEntry {
  RaindropMigrationEntry({
    this.id,
    required this.name,
    required this.appliedAt,
    required this.checksum,
  });

  final int? id;
  final String name;
  final DateTime appliedAt;
  final String checksum;
}

class RaindropMigrationsTable extends Table<RaindropMigrationEntry> {
  RaindropMigrationsTable(super.$)
    : id = $.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
      name = $.text('tag', (s) => s.name),
      appliedAt = $.dateTime('applied_at', (s) => s.appliedAt),
      checksum = $.text('checksum', (s) => s.checksum);

  final IntColumn id;
  final TextColumn name;
  final DateTimeColumn appliedAt;
  final TextColumn checksum;

  @override
  RaindropMigrationEntry fromRow(RowReader read) {
    return RaindropMigrationEntry(
      id: read(id),
      name: read(name)!,
      appliedAt: read(appliedAt)!,
      checksum: read(checksum)!,
    );
  }
}

final raindropMigrations = table(
  '_raindrop_migrations',
  RaindropMigrationsTable.new,
  (table) {
    uniqueIndex('raindrop_migrations_name_unique').on(table.name);
  },
);
