import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_schema/src/internal/tables.dart';
import 'package:zonai_schema/src/internal/photos_table.dart' as schema;

class PhotosTable extends schema.PhotosTable {
  PhotosTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PhotoId.new,
        generate: PhotoId.generate,
      ),
      ownerId = $.id<UnknownId, UnknownId>(
        'owner_id',
        (s) => UnknownId(s.ownerId.value),
        fromString: UnknownId.new,
        synthetic: const UnknownId('__PHOTO_OWNER__'),
        generate: () => throw Exception('Owner ID is required for photos'),
        isPrimaryKey: false,
      ),
      ownerTable = $.text('owner_collection', (s) => s.ownerTable),
      collection = $.text('table', (s) => s.table),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      path = $.text('path', (s) => s.path),
      extension = $.text('extension', (s) => s.extension);

  @override
  PhotoEntry fromRow(RowReader read) {
    return PhotoEntry(
      id: read(id),
      ownerId: read(ownerId),
      ownerTable: read(ownerTable),
      table: read(collection),
      createdAt: read(createdAt),
      path: read(path),
      extension: read(extension),
    );
  }

  final IdColumn<PhotoId> id;
  final IdColumn<UnknownId> ownerId;
  final TextColumn ownerTable;
  final TextColumn collection;
  final DateTimeColumn createdAt;
  final TextColumn path;
  final TextColumn extension;
}

final photos = () {
  final photos = table('_photos', PhotosTable.new);

  setupInternalTables(photos: photos);

  return photos;
}();
