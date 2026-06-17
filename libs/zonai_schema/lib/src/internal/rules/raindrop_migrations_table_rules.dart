import 'package:zonai_schema/src/internal/built_in_tables/raindrop_migrations_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';

RaindropMigrationsTableRules main() => RaindropMigrationsTableRules();

final class RaindropMigrationsTableRules
    extends
        InternalTableRules<RaindropMigrationsTable, RaindropMigrationEntry> {
  RaindropMigrationsTableRules() : super(raindropMigrations);
}
