import 'dart:convert';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/tables/photos_table.dart' as photos_table;

extension PhotosColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> photos<W extends List<photos_table.PhotoId>?>(
    String name,
    Field<S, W> field,
  ) {
    final column = custom<List<photos_table.PhotoId>, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const PhotosTransformer(),
    );

    return column.references(() => photos_table.photos.id);
  }
}

class PhotosTransformer extends ColumnTransformer<List<photos_table.PhotoId>, String> {
  const PhotosTransformer();

  @override
  String encode(List<photos_table.PhotoId> input) =>
      jsonEncode(input.map((e) => e.value).toList());

  @override
  List<photos_table.PhotoId> decode(String input) =>
      jsonDecode(input).map((e) => photos_table.PhotoId(e)).toList();
}
