import 'package:zonai/src/internal/built_in_tables/raindrop_migrations_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';

RaindropMigrationsRowRules main() => RaindropMigrationsRowRules();

final class RaindropMigrationsRowRules
    extends InternalRowRules<RaindropMigrationsTable, RaindropMigrationEntry> {
  RaindropMigrationsRowRules() : super(raindropMigrations);
}
