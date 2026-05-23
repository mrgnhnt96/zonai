import 'package:zonai/src/internal/raindrop_migrations_collection.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';

RaindropMigrationsRecordRules main() => RaindropMigrationsRecordRules();

final class RaindropMigrationsRecordRules
    extends InternalRecordRules<RaindropMigrationsCollection, RaindropMigrationEntry> {
  RaindropMigrationsRecordRules() : super(raindropMigrations);
}
