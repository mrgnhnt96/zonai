import 'package:raindrop/raindrop.dart';

// TODO(mrgnhnt): Make sure that the password is hashed before
// it is stored in the database.
// Also, make sure that the password
extension PasswordColumnDefinition<S extends Schema<S>> on SchemaBuilder<S> {
  T password<T extends PasswordColumn?>(
    String name,
    Field<S, T> field,
    String? value,
  ) {
    return custom<String, String, PasswordColumn, T>(
          PasswordColumn.new,
          name,
          field,
          value,
          sqlType: 'TEXT',
          transformer: const PasswordTransformer(),
        )
        as T;
  }
}

extension type PasswordColumn(String _) implements ColumnType<String>, String {}

class PasswordTransformer extends ColumnTransformer<String, String>
    implements SecretTransformer<String, String> {
  const PasswordTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}

/// A transformer that transforms a secret value
///
/// Filters out the value during sanitization
abstract interface class SecretTransformer<T, O>
    extends ColumnTransformer<T, O> {
  const SecretTransformer();
}
