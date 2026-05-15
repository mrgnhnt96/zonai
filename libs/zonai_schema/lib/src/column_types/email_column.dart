import 'package:raindrop/raindrop.dart';

extension EmailColumnDefinition<S> on SchemaBuilder<S> {
  T email<T extends EmailColumn?>(String name, Field<S, String> field) {
    return custom(
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
