import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/src/transformers/secret_transformer.dart';

extension PasswordColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> password<W extends String?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<String, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const PasswordTransformer(),
    );
  }
}

class PasswordTransformer extends ColumnTransformer<String, String>
    implements SecretTransformer<String, String> {
  const PasswordTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
