import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';

extension PasswordColumnDefinition<S> on SchemaBuilder<S> {
  T password<T extends PasswordColumn?>(String name, Field<S, String> field) {
    return custom(
          PasswordColumn.new,
          name,
          field,
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
