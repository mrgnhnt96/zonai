import 'package:zonai_schema/src/internal/raindrop_migrations_collection.dart';
import 'package:zonai_schema/src/internal/rules/internal_rules.dart';

RaindropMigrationsCollectionRules main() => RaindropMigrationsCollectionRules();

final class RaindropMigrationsCollectionRules
    extends InternalCollectionRules<RaindropMigrationsCollection, RaindropMigrationEntry> {
  RaindropMigrationsCollectionRules() : super(raindropMigrations);
}
