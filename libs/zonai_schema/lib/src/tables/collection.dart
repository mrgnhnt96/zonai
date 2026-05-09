import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/schemas/auth.dart';

/// Defines a database-backed collection with the given [name] and [builder].
///
/// Optionally, you can provide an [indexes] callback to define indexes on the
/// collection. The callback receives the collection's schema instance and can use
/// the [index] function to define indexes.
///
/// Example:
/// ```dart
/// final users = collection('users', () => User(...));
///
/// // With indexes:
/// final pets = collection(
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
S collection<S extends Schema<S>>(
  String name,
  S Function() builder, [
  void Function(S table)? extra,
]) {
  if (S is Auth) {
    throw Exception(
      '`authCollection` should be used instead of `collection` for schemas that extend `Auth`',
    );
  }

  return table(name, builder, dialect: 'sqlite', extra: extra);
}
