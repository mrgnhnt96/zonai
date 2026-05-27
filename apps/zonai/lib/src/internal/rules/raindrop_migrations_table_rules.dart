import 'package:zonai/src/internal/built_in_tables/raindrop_migrations_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';

RaindropMigrationsTableRules main() => RaindropMigrationsTableRules();

final class RaindropMigrationsTableRules
    extends
        InternalTableRules<RaindropMigrationsTable, RaindropMigrationEntry> {
  RaindropMigrationsTableRules() : super(raindropMigrations);
}
