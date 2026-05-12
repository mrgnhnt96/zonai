import 'package:raindrop/raindrop.dart';

extension EmailColumnDefinition<S extends Schema<S>> on SchemaBuilder<S> {
  T email<T extends EmailColumn?>(
    String name,
    Field<S, T> field,
    String? value,
  ) {
    return custom<String, String, EmailColumn, T>(
          EmailColumn.new,
          name,
          field,
          value,
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
