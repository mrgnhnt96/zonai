import 'package:raindrop/raindrop.dart';

extension EmailColumnDefinition<S> on SchemaBuilder<S> {
  T email<T extends EmailColumn?, W extends String?>(
    String name,
    W Function(S) field,
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

extension type EmailColumn(Column<dynamic, String> _)
    implements ColumnType<String> {}

class EmailTransformer extends ColumnTransformer<String, String> {
  const EmailTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
