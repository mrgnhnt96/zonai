import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';

extension SecretColumnDefinition<S> on SchemaBuilder<S> {
  /// A `TEXT` column whose value is stripped from every response.
  ///
  /// Shares the sanitization behaviour of `$.password` -- `_sanitizeRows`
  /// removes every [SecretTransformer] column on the way out, and a `where`
  /// that filters on one is refused -- and none of the password *semantics*.
  /// The value is stored exactly as given (never Argon2-hashed on write), and
  /// `GetColumnNameRequest(columnName: .password)` does not resolve to it,
  /// because that lookup type-checks for `PasswordTransformer` specifically
  /// (`db_operations.dart:563`).
  ///
  /// For a value the server must compare against but no client may read back:
  /// an API token's SHA-256, for instance.
  ColumnType<W> secret<W extends String?>(String name, Field<S, W> field) {
    return custom<String, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const SecretTextTransformer(),
    );
  }
}

/// Identity encode/decode -- the column stores what it is given. The type is
/// the whole point: it is what `is SecretTransformer` checks see.
class SecretTextTransformer extends ColumnTransformer<String, String>
    implements SecretTransformer<String, String> {
  const SecretTextTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
