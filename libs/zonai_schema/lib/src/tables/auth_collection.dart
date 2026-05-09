import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Defines an auth-related database-backed collection with the given [name] and [builder].
///
/// You may optionally provide an [indexes] callback to define additional indexes particular
/// to your authentication model. The callback receives the schema instance for the collection,
/// allowing you to use [index] and [uniqueIndex] for securing and efficiently querying auth data.
///
/// Example:
/// ```dart
/// class User extends PasswordAuth<User> { ... }
///
/// final users = authCollection('users', () => User(...));
///
/// // With custom auth indexes:
/// final apiKeys = authCollection(
///   'api_keys',
///   () => ApiKeyAuth(
///     id: ApiKeyId.generate(),
///     key: fakes.text(),
///     userId: fakes.integer(),
///   ),
///   (table) {
///     // Index to quickly look up by key
///     uniqueIndex('api_keys_key_unique').on(table.key);
///
///     // Composite index for API key and user lookup
///     index('api_keys_userid_key').on(table.userId, table.key);
///   },
/// );
/// ```
//
S authCollection<S extends AuthCollection<S>>(
  String name,
  S Function() builder, [
  void Function(S table)? extra,
]) {
  return table(
    name,
    builder,
    dialect: 'sqlite',
    extra: (table) {
      if (extra case final extra?) {
        extra.call(table);

        for (final index in Table.getFor(table).indexes) {
          if (index.columns.contains(table.id)) {
            if (index.isUnique) {
              continue;
            }

            throw Exception(
              'Unique index on id column is required for auth collections: $name',
            );
          }
        }
      } else {
        uniqueIndex('${name}.id_unique').on(table.id);
      }
    },
  );
}
