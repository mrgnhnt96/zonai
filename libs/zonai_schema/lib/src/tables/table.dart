import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/src/schemas/table.dart';

/// Defines a database-backed table with the given [name] and [builder].
///
/// Optionally, you can provide an [indexes] callback to define indexes on the
/// collection. The callback receives the table's schema instance and can use
/// the [index] function to define indexes.
///
/// Example:
/// ```dart
/// final users = table('users', () => User(...));
///
/// // With indexes:
/// final pets = table(
///   'pets',
///   () => Pet(
///     id: fakes.primaryKey(),
///     userId: fakes.integer(),
///     name: fakes.text(),
///   ),
///   (table) {
///     // Single column index
///     index('pets_user_id').on(table.userId);
///
///     // Unique index
///     uniqueIndex('pets_name_unique').on(table.name);
///
///     // Composite index using record syntax
///     index('pets_composite').on(table.userId, table.name);
///   },
/// );
/// ```
S table<S extends Table<T>, T>(
  String name,
  S Function(rd.SchemaBuilder<T>) builder, [
  void Function(S table)? extra,
]) {
  return rd.table(name, builder, dialect: 'sqlite', extra: extra);
}
