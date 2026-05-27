import 'dart:convert';

import 'package:raindrop/raindrop.dart';

extension PhotosColumnDefinition<S> on SchemaBuilder<S> {
  T photos<T extends PhotosColumn?>(String name, Field<S, List<String>> field) {
    return custom(
          PhotosColumn.new,
          name,
          field,
          sqlType: 'TEXT',
          transformer: const PhotosTransformer(),
        )
        as T;
  }
}

extension type PhotosColumn(List<String> _)
    implements ColumnType<List<String>>, List<String> {}

class PhotosTransformer extends ColumnTransformer<List<String>, String> {
  const PhotosTransformer();

  @override
  String encode(List<String> input) => jsonEncode(input);

  @override
  List<String> decode(String input) => jsonDecode(input);
}
