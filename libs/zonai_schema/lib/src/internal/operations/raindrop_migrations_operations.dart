import 'package:zonai_schema/src/internal/built_in_tables/raindrop_migrations_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class RaindropMigrationsOperations
    extends TableOperations<RaindropMigrationsTable, RaindropMigrationEntry> {
  RaindropMigrationsOperations() : super(raindropMigrations);
}

RaindropMigrationsOperations main() => RaindropMigrationsOperations();
