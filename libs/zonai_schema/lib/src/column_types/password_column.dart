import 'package:raindrop/raindrop.dart' hide Table;
import 'package:zonai_schema/src/transformers/secret_transformer.dart';

extension PasswordColumnDefinition<S> on SchemaBuilder<S> {
  T password<T extends PasswordColumn?, W extends String?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<PasswordColumn, String, String, W>(
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
