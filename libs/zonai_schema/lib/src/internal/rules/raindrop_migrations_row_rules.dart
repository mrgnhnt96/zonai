import 'package:zonai_schema/src/internal/built_in_tables/raindrop_migrations_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';

RaindropMigrationsRowRules main() => RaindropMigrationsRowRules();

final class RaindropMigrationsRowRules
    extends InternalRowRules<RaindropMigrationsTable, RaindropMigrationEntry> {
  RaindropMigrationsRowRules() : super(raindropMigrations);
}
