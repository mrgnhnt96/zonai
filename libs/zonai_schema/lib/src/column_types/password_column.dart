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
    return column<String, PasswordColumn, T>(
          PasswordColumn.new,
          name,
          field,
          value,
          sqlType: 'TEXT',
        )
        as T;
  }
}

extension type PasswordColumn(String _) implements ColumnType<String>, String {}
