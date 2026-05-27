import 'package:zonai/src/internal/raindrop_migrations_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';

RaindropMigrationsRecordRules main() => RaindropMigrationsRecordRules();

final class RaindropMigrationsRecordRules
    extends InternalRecordRules<RaindropMigrationsTable, RaindropMigrationEntry> {
  RaindropMigrationsRecordRules() : super(raindropMigrations);
}
