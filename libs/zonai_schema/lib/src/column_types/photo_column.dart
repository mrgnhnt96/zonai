import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/internal/photos_table.dart';
import 'package:zonai_schema/src/internal/tables.dart'
    show ensureInternalTablesForIntrospection, photos;

extension PhotoColumnDefinition<S> on SchemaBuilder<S> {
  T photo<T extends PhotoColumn?, W extends PhotoId?>(
    String name,
    W Function(S) field,
  ) {
    final c =
        custom<PhotoColumn, PhotoId, String, W>(
              PhotoColumn.new,
              name,
              field,
              sqlType: 'TEXT',
              transformer: const PhotoTransformer(),
            )
            as PhotoColumn?;

    ensureInternalTablesForIntrospection();
    return c?.references(() => photos.id) as T;
  }
}

extension type PhotoColumn(Column<dynamic, PhotoId> _)
    implements ColumnType<PhotoId> {}

class PhotoTransformer extends ColumnTransformer<PhotoId, String> {
  const PhotoTransformer();

  @override
  String encode(PhotoId input) => input.value;

  @override
  PhotoId decode(String input) => PhotoId(input);
}
