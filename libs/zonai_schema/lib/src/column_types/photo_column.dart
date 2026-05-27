import 'package:raindrop/raindrop.dart';

extension PhotoColumnDefinition<S> on SchemaBuilder<S> {
  T photo<T extends PhotoColumn?, W extends String?>(
    String name,
    Field<S, W> field,
  ) {
    return custom<PhotoColumn, String, String, W>(
          PhotoColumn.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: const PhotoTransformer(),
        )
        as T;
  }
}

extension type PhotoColumn(String _) implements ColumnType<String>, String {}

class PhotoTransformer extends ColumnTransformer<String, String> {
  const PhotoTransformer();

  @override
  String encode(String input) => input;

  @override
  String decode(String input) => input;
}
