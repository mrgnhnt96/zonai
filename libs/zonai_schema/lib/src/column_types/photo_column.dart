import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/tables/photos_table.dart';

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
