import 'package:raindrop/raindrop.dart';

extension EmailColumnDefinition<S> on SchemaBuilder<S> {
  T email<T extends EmailColumn?, W extends String?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<EmailColumn, String, String, W>(
          EmailColumn.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: const EmailTransformer(),
        )
        as T;
  }
}

extension type EmailColumn(String _) implements ColumnType<String>, String {}

class EmailTransformer extends ColumnTransformer<String, String> {
  const EmailTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
