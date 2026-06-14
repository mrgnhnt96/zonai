import 'dart:convert';

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/photos_table.dart';
import 'package:zonai_schema/src/internal/tables.dart'
    as tables
    show ensureInternalTablesForIntrospection, photos;

extension PhotosColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> photos<W extends List<PhotoId>?>(
    String name,
    Field<S, W> field,
  ) {
    final column = custom<List<PhotoId>, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const PhotosTransformer(),
    );

    tables.ensureInternalTablesForIntrospection();
    return column.references(() => tables.photos.id);
  }
}

class PhotosTransformer extends ColumnTransformer<List<PhotoId>, String> {
  const PhotosTransformer();

  @override
  String encode(List<PhotoId> input) =>
      jsonEncode(input.map((e) => e.value).toList());

  @override
  List<PhotoId> decode(String input) =>
      jsonDecode(input).map((e) => PhotoId(e)).toList();
}
