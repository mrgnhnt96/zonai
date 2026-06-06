import 'dart:convert';

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/photos_table.dart';
import 'package:zonai_schema/src/internal/tables.dart'
    as tables
    show ensureInternalTablesForIntrospection, photos;

extension PhotosColumnDefinition<S> on SchemaBuilder<S> {
  T photos<T extends PhotosColumn?, W extends List<PhotoId>?>(
    String name,
    W Function(S) field,
  ) {
    final c =
        custom<PhotosColumn, List<PhotoId>, String, W>(
              PhotosColumn.new,
              name,
              field,
              sqlType: 'TEXT',
              transformer: const PhotosTransformer(),
            )
            as PhotosColumn?;

    tables.ensureInternalTablesForIntrospection();
    return c?.references(() => tables.photos.id) as T;
  }
}

extension type PhotosColumn(Column<dynamic, List<PhotoId>> _)
    implements ColumnType<List<PhotoId>> {}

class PhotosTransformer extends ColumnTransformer<List<PhotoId>, String> {
  const PhotosTransformer();

  @override
  String encode(List<PhotoId> input) =>
      jsonEncode(input.map((e) => e.value).toList());

  @override
  List<PhotoId> decode(String input) =>
      jsonDecode(input).map((e) => PhotoId(e)).toList();
}
