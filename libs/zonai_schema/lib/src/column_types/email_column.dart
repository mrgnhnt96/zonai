import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

extension EmailColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> email<W extends String?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<String, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const EmailTransformer(),
    );
  }
}

class EmailTransformer extends ColumnTransformer<String, String> {
  const EmailTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
