import 'package:zonai_schema/src/internal/raindrop_migrations_collection.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';

final class RaindropMigrationsOperations
    extends
        CollectionOperations<
          RaindropMigrationsCollection,
          RaindropMigrationEntry
        > {
  RaindropMigrationsOperations() : super(raindropMigrations);
}

RaindropMigrationsOperations main() => RaindropMigrationsOperations();
