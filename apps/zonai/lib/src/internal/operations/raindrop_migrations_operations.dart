import 'package:zonai/src/internal/raindrop_migrations_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class RaindropMigrationsOperations
    extends
        TableOperations<
          RaindropMigrationsTable,
          RaindropMigrationEntry
        > {
  RaindropMigrationsOperations() : super(raindropMigrations);
}

RaindropMigrationsOperations main() => RaindropMigrationsOperations();
