import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Implemented by [ColumnTransformer]s whose primary-key columns should receive a
/// server-generated value when hydrating partial rows (for example rules
/// evaluation on create payloads that omit `id`).
mixin CreatePrimaryKey<T> {
  String encode(T input);

  /// Wire/storage shape understood by this transformer’s [ColumnTransformer.decode].
  T primaryKey();

  Object encodedPrimaryKey() => encode(primaryKey());
}
