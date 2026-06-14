import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/photos_table.dart';
import 'package:zonai_schema/src/internal/tables.dart'
    show ensureInternalTablesForIntrospection, photos;

extension PhotoColumnDefinition<S> on SchemaBuilder<S> {
  ColumnType<W> photo<W extends PhotoId?>(
    String name,
    Field<S, W> field,
  ) {
    final column = custom<PhotoId, String, W>(
      name,
      field,
      sqlType: 'TEXT',
      transformer: const PhotoTransformer(),
    );

    ensureInternalTablesForIntrospection();
    return column.references(() => photos.id);
  }
}

class PhotoTransformer extends ColumnTransformer<PhotoId, String> {
  const PhotoTransformer();

  @override
  String encode(PhotoId input) => input.value;

  @override
  PhotoId decode(String input) => PhotoId(input);
}
