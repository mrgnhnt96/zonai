import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_schema/src/internal/collections.dart';
import 'package:zonai_schema/src/internal/photos_collection.dart' as schema;

class PhotosCollection extends schema.PhotosCollection {
  PhotosCollection(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PhotoId.new,
        generate: PhotoId.generate,
      ),
      ownerId = $.id(
        'owner_id',
        (s) => s.ownerId,
        fromString: UnknownId.new,
        synthetic: const UnknownId('__PHOTO_OWNER__'),
        generate: () => throw Exception('Owner ID is required for photos'),
        isPrimaryKey: false,
      ),
      ownerCollection = $.text('owner_collection', (s) => s.ownerCollection),
      collection = $.text('collection', (s) => s.collection),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      path = $.text('path', (s) => s.path),
      extension = $.text('extension', (s) => s.extension);

  @override
  PhotoEntry fromRow(RowReader read) {
    return PhotoEntry(
      id: read(id),
      ownerId: read(ownerId),
      ownerCollection: read(ownerCollection),
      collection: read(collection),
      createdAt: read(createdAt),
      path: read(path),
      extension: read(extension),
    );
  }

  final IdColumn<PhotoId> id;
  final IdColumn<UnknownId> ownerId;
  final TextColumn ownerCollection;
  final TextColumn collection;
  final DateTimeColumn createdAt;
  final TextColumn path;
  final TextColumn extension;
}

final photos = () {
  final c = collection('_photos', PhotosCollection.new);

  setupInternalCollections(photos: c);

  return c;
}();
