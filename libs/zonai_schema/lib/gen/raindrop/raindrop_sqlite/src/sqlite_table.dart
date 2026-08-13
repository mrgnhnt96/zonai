// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';

/// Creates a SQLite table with the given [name] and [builder].
///
/// Example:
/// ```dart
/// final users = sqliteTable('users', UserSchema.new);
///
/// // With indexes:
/// final pets = sqliteTable(
///   'pets',
///   PetSchema.new,
///   (table) {
///     index('pets_owner').on(table.ownerId);
///     uniqueIndex('pets_name_unique').on(table.name);
///     index('pets_composite').on(table.ownerId, table.name);
///   },
/// );
/// ```
S sqliteTable<S extends Schema<R>, R>(
  String name,
  S Function(SchemaBuilder<R>) builder, [
  void Function(S table)? extra,
]) {
  return table<S, R>(name, builder, dialect: dialect, extra: extra);
}
